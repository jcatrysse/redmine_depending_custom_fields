# frozen_string_literal: true

# QA-19 stored-cycle fixtures (WP-10): depending fields whose stored parent
# pointers form a cycle. Saves refuse such pointers since WP-10, so the
# pointers are written into format_store without callbacks or validation,
# as data from before WP-10 (or from the concurrent-creation race) would be;
# every builder checks the stored state. Reused by later work packages for
# the context menu (WP-15) and the issue-form attributes (WP-16).
module DcfStoredCycle
  include DcfFormatCharacterization

  # x <-> y (x1 allows y1, y1 allows x1), child below x (x1 allows c1),
  # self_parent naming itself (s1 allows s1), below_self_parent below it (s1
  # allows d1), the 3-cycle a -> b -> c -> a (a names b, b names c, c names
  # a) and a plain root. Every depending field has values allowed by no
  # parent value.
  StoredCycles = Struct.new(:x, :y, :child, :self_parent, :below_self_parent, :a, :b, :c, :root,
                            keyword_init: true) do
    def depending
      [x, y, child, self_parent, below_self_parent, a, b, c]
    end
  end

  # Writes +parent+ (a field or an id; nil clears it) as the stored pointer
  # of +field+ and returns a fresh instance. Raises when the database does
  # not hold the pointer afterwards.
  def dcf_store_parent(field, parent)
    pid = parent.respond_to?(:id) ? parent.id : parent
    store = CustomField.find(field.id).format_store.to_hash.merge('parent_custom_field_id' => pid)
    raw = CustomField.type_for_attribute('format_store').serialize(store)
    CustomField.where(id: field.id).update_all(['format_store = ?', raw])
    stored = CustomField.find(field.id)
    raise "stored pointer of field #{field.id} was not written" unless stored.parent_custom_field_id == pid

    stored
  end

  # A depending field of +kind+ (:list or :enumeration) with +names+ as
  # values and +parent+ as its saved parent (nil for none).
  def dcf_cycle_field(kind, names, parent: nil, name: nil)
    if kind == :list
      dcf_list_field(format: 'depending_list', values: names, parent: parent, name: name)
    else
      dcf_enum_field(format: 'depending_enumeration', names: names, parent: parent, name: name)
    end
  end

  # Stores +links+ (parent name => child names) as the mapping of +field+,
  # whose parent is +parent+, through a normal save (the pointer is not
  # changed, so no cycle check runs). Returns the reloaded field.
  def dcf_cycle_links(field, parent, links)
    mapping = links.to_h { |pname, cnames| [kit_key(parent, pname), cnames.map { |n| kit_key(field, n) }] }
    dcf_set_dependencies(CustomField.find(field.id), value_dependencies: mapping)
  end

  def dcf_stored_cycles(kind)
    root = kind == :list ? dcf_list_field(values: %w[r1 r2]) : dcf_enum_field(names: %w[r1 r2])
    x = dcf_cycle_field(kind, %w[x1 x2], name: "X-#{SecureRandom.hex(3)}")
    y = dcf_cycle_field(kind, %w[y1 y2], parent: x, name: "Y-#{SecureRandom.hex(3)}")
    x = dcf_store_parent(x, y)
    child = dcf_cycle_field(kind, %w[c1 c2], parent: x)
    self_parent = dcf_store_parent(dcf_cycle_field(kind, %w[s1 s2], name: "S-#{SecureRandom.hex(3)}"), nil)
    self_parent = dcf_store_parent(self_parent, self_parent)
    below_self_parent = dcf_cycle_field(kind, %w[d1 d2], parent: self_parent)
    a = dcf_cycle_field(kind, %w[a1 a2], name: "A-#{SecureRandom.hex(3)}")
    c = dcf_cycle_field(kind, %w[k1 k2], parent: a, name: "C-#{SecureRandom.hex(3)}")
    b = dcf_cycle_field(kind, %w[b1 b2], parent: c, name: "B-#{SecureRandom.hex(3)}")
    a = dcf_store_parent(a, b)

    StoredCycles.new(
      x: dcf_cycle_links(x, y, 'y1' => %w[x1]),
      y: dcf_cycle_links(y, x, 'x1' => %w[y1]),
      child: dcf_cycle_links(child, x, 'x1' => %w[c1]),
      self_parent: dcf_cycle_links(self_parent, self_parent, 's1' => %w[s1]),
      below_self_parent: dcf_cycle_links(below_self_parent, self_parent, 's1' => %w[d1]),
      a: dcf_cycle_links(a, b, 'b1' => %w[a1]),
      b: dcf_cycle_links(b, c, 'k1' => %w[b1]),
      c: dcf_cycle_links(c, a, 'a1' => %w[k1]),
      root: root
    ).tap { |world| dcf_check_stored_cycles(world) }
  end

  def dcf_check_stored_cycles(world)
    expected = {
      world.x => world.y, world.y => world.x, world.child => world.x, world.self_parent => world.self_parent,
      world.below_self_parent => world.self_parent, world.a => world.b, world.b => world.c, world.c => world.a
    }
    expected.each do |field, parent|
      stored = CustomField.find(field.id).parent_custom_field_id
      raise "stored cycle fixture: #{field.name} names #{stored.inspect}, not #{parent.id}" unless stored == parent.id
    end
  end
end
