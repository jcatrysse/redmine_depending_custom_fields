(function() {
  function updateChild(parentSelect, childSelect, mapping) {
    var parentValue = parentSelect.value;
    var allowed = mapping[parentValue] || [];
    var options = childSelect.querySelectorAll('option');
    options.forEach(function(opt) {
      if (opt.value === '') {
        opt.hidden = false;
      } else {
        opt.hidden = allowed.length > 0 && allowed.indexOf(opt.value) === -1;
      }
    });
    if (!parentValue) {
      childSelect.disabled = true;
      childSelect.value = '';
    } else {
      childSelect.disabled = false;
      if (allowed.length > 0 && allowed.indexOf(childSelect.value) === -1) {
        childSelect.value = '';
      }
    }
    childSelect.dispatchEvent(new Event('change'));
  }

  document.addEventListener('DOMContentLoaded', function() {
    var data = window.DependingCustomFieldData || {};
    Object.keys(data).forEach(function(cid) {
      var info = data[cid];
      var childSelect = document.getElementById('issue_custom_field_values_' + cid);
      var parentSelect = document.getElementById('issue_custom_field_values_' + info.parent_id);
      if (!childSelect || !parentSelect) { return; }
      childSelect.classList.add('depending-child');
      parentSelect.addEventListener('change', function() {
        updateChild(parentSelect, childSelect, info.map || {});
      });
      updateChild(parentSelect, childSelect, info.map || {});
    });
  });
})();
