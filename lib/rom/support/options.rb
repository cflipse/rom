module ROM
  # Helper module for classes with a constructor accepting option hash
  #
  # This allows us to DRY up code as option hash is a very common pattern used
  # across the codebase. It is an internal implementation detail not meant to
  # be used outside of ROM
  #
  # @example
  #   class User
  #     include Options
  #
  #     option :name, type: String, reader: true
  #     option :admin, allow: [true, false], reader: true, default: false
  #
  #     def initialize(options={})
  #       super
  #     end
  #   end
  #
  #   user = User.new(name: 'Piotr')
  #   user.name # => "Piotr"
  #   user.admin # => false
  #
  # @api public
  module Options
    # @return [Hash<Option>] Option definitions
    #
    # @api public
    attr_reader :options

    def self.included(klass)
      klass.class_eval do
        extend(ClassMethods)

        def self.inherited(descendant)
          descendant.instance_variable_set('@__options__', option_definitions.dup)
          super
        end
      end
    end

    # Defines a single option
    #
    # @api private
    class Option
      attr_reader :name, :type, :allow, :default

      def initialize(name, options = {})
        @name = name
        @type = options.fetch(:type) { Object }
        @reader = options.fetch(:reader) { false }
        @allow = options.fetch(:allow) { [] }
        @default = options.fetch(:default) { Undefined }
      end

      def reader?
        @reader
      end

      def default?
        @default != Undefined
      end

      def default_value(object)
        default.is_a?(Proc) ? default.call(object) : default
      end

      def type_matches?(value)
        value.is_a?(type)
      end

      def allow?(value)
        allow.none? || allow.include?(value)
      end
    end

    # Manage all available options
    #
    # @api private
    class Definitions
      def initialize
        @options = {}
      end

      def initialize_copy(source)
        super
        @options = @options.dup
      end

      def define(option)
        @options[option.name] = option
      end

      def validate_options(options)
        options.each do |name, value|
          validate_option_value(name, value)
        end
      end

      def set_defaults(object, options)
        each do |name, option|
          next unless option.default? && !options.key?(name)
          options[name] = option.default_value(object)
        end
      end

      def set_option_values(object, options)
        each do |name, option|
          object.instance_variable_set("@#{name}", options[name]) if option.reader?
        end
      end

      private

      def each(&block)
        @options.each(&block)
      end

      def validate_option_value(name, value)
        option = @options.fetch(name) do
          raise InvalidOptionKeyError,
            "#{name.inspect} is not a valid option"
        end

        unless option.type_matches?(value)
          raise InvalidOptionValueError,
            "#{name.inspect}:#{value.inspect} has incorrect type"
        end

        unless option.allow?(value)
          raise InvalidOptionValueError,
            "#{name.inspect}:#{value.inspect} has incorrect value"
        end
      end
    end

    # @api private
    module ClassMethods
      # Available options
      #
      # @return [Definitions]
      #
      # @api private
      def option_definitions
        @__options__ ||= Definitions.new
      end

      # Defines an option
      #
      # @param [Symbol] name option name
      #
      # @param [Hash] settings option settings
      # @option settings [Class] :type Restrict option type. Default: +Object+
      # @option settings [Boolean] :reader Define a reader? Default: +false+
      # @option settings [Array] :allow Only allow certain values. Default: Allow anything
      # @option settings [Object] :default Set default value if option is missing. Default: +nil+
      #
      # @api public
      def option(name, settings = {})
        option = Option.new(name, settings)
        option_definitions.define(option)
        attr_reader(name) if option.reader?
      end
    end

    # Initialize options provided as optional last argument hash
    #
    # @example
    #   class Commands
    #     include Options
    #
    #     # ...
    #
    #     def initialize(relations, options={})
    #       @relation = relation
    #       super
    #     end
    #   end
    #
    # @param [Array] args
    def initialize(*args)
      options = args.last ? args.last.dup : {}
      definitions = self.class.option_definitions
      definitions.set_defaults(self, options)
      definitions.validate_options(options)
      definitions.set_option_values(self, options)
      @options = options.freeze
    end
  end
end
