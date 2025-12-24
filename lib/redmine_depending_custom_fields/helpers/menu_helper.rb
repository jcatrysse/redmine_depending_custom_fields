module RedmineDependingCustomFields
  module Helpers
    module MenuHelper
      module SafeMenuAdd
        def add(name, url = {}, options = {})
          super
        rescue IndexError
          fallback = options.dup
          fallback.delete(:position)
          fallback.delete(:after)
          fallback.delete(:before)
          super(name, url, fallback)
        end
      end

      def self.safe_add(menu, name, url = {}, options = {})
        begin
          menu.add(name, url, options)
        rescue IndexError => e
          # Position was out of bounds, fallback: remove position-related keys and push last
          fallback = options.dup
          fallback.delete(:position)
          fallback.delete(:after)
          fallback.delete(:before)
          # If menu.push exists (older/newer Redmine variations), use it; else add without options
          if menu.respond_to?(:push)
            menu.push(name, url, fallback)
          else
            menu.add(name, url, fallback)
          end
        end
      end
    end
  end
end

if defined?(Redmine::MenuManager::Menu) &&
   !Redmine::MenuManager::Menu.ancestors.include?(RedmineDependingCustomFields::Helpers::MenuHelper::SafeMenuAdd)
  Redmine::MenuManager::Menu.prepend(RedmineDependingCustomFields::Helpers::MenuHelper::SafeMenuAdd)
end
