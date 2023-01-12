require "factory_bot"
require "active_support/inflector/methods"

# This file contains code allowing creating OpenAPI examples using FactoryBot,
# with almost the same DSL, and avoiding declaring same factories as already
# being defined in tests/factories.
#
# Main differences are:
# - `BulletTrain::Api` class instead of `FactoryBot`
# - `example` definition keyword instead of `factory`
# - `example` method instead of `create`
#
# Example:
#   BulletTrain::Api.define do
#     example :team do
#       name 'Awesome Team'
#     end
#
#     example :user do
#       association :current_team, example: :team
#     end
#   end
#
#   > post = BulletTrain::Api.example(:post)
#   > #<Team...>
#   >
#   > post.author
#   > #<User...>
module BulletTrain
  module Api
    module ExampleBot
      class DSL
        attr_accessor :version

        def initialize(version)
          @version = version
        end

        # Replaces FactoryBot's `factory` method.
        #
        # Example:
        #   example :user do
        #     name 'Joey'
        #   end
        def example(name, **options, &block)
          options[:class] ||= name.to_s.pluralize.classify
          name = BulletTrain::Api.example_name(name, @version)

          FactoryBot.define { factory(name, **options, &block) }
        end

        def self.run(version, &block)
          new(version).instance_eval(&block)
        end
      end

      # Suffix added to FactoryBot factory names to separate them from factories used in tests
      # It should never be seen for the end user
      SUFFIX = "-bullet_train-api-example-"

      # This are the folders where OpenAPI examples are supposed to be stored
      FactoryBot.definition_file_paths += Dir.glob("app/views/api/v*/open_api/examples")

      # Extracts example file version from it's path
      def example_version(path)
        path.match(/app\/views\/api\/(..)\/open_api\/examples/).captures.first
      end

      # Generates example name from model, suffix and version
      def example_name(model, version = nil)
        version ||= "v1"
        "#{model}#{SUFFIX}#{version}"
      end

      # Replaces FactoryBot's `define` method.
      #
      # Example:
      #   BulletTrain::Api.define do
      #     ...
      #   end
      def define(&block)
        DSL.run(example_version(caller.first), &block)
      end

      # Replaces FactoryBot's `create` or `build` methods.
      #
      # Example:
      #   BulletTrain::Api.example(:user)
      def example(model, **options)
        object = FactoryBot.build(example_name(model, options.delete(:version)), **options)
        object.id ||= 1
        object.created_at = Time.now if object.respond_to?(:created_at?)
        object.updated_at = Time.now if object.respond_to?(:updated_at?)
        object
      end

      # Replaces FactoryBot's `create_list` or `build_list` methods.
      #
      # Example:
      #   BulletTrain::Api.example_list(:user, 10)
      def example_list(model, quantity, **options)
        objects = FactoryBot.build_list(example_name(model, options.delete(:version)), quantity, **options)
        objects.map.with_index do |object, index|
          object.id ||= index + 1
          object.created_at = Time.now if object.respond_to?(:created_at?)
          object.updated_at = Time.now if object.respond_to?(:updated_at?)
        end
        objects
      end
    end

    extend ExampleBot
  end
end

module FactoryBot
  class DefinitionProxy
    # Allows nested examples.
    #
    # Example:
    #   example :user do
    #     name 'Joey'
    #
    #     example :invited_user do
    #       invited true
    #     end
    #   end
    def example(name, **options, &block)
      version = options.delete(:version) || BulletTrain::Api.example_version(caller.first)
      name = BulletTrain::Api.example_name(name, version)
      @child_factories << [name, options, block]
    end
  end

  class Declaration
    # Allows using BulletTrain::Api.example instead of FactoryBot.factory when declaring associations.
    #
    # Example:
    #   example :team do
    #     name 'Awesome Team'
    #   end
    #
    #   example :user do
    #     association :current_team, example: :team # Always use the exactly this construction
    #   end
    class Association < Declaration
      def initialize(name, *options)
        super(name, false)
        @options = options.dup
        @overrides = options.extract_options!
        @overrides[:example] = BulletTrain::Api.example_name(@overrides[:example], @overrides[:version]) if @overrides[:example]
        @factory_name = @overrides.delete(:example) || @overrides.delete(:factory) || name
        @traits = options
      end
    end
  end
end
