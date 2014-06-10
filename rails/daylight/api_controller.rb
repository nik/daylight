##
# Common conntroller built on top of `ApplicationController` that assists with
# setting up standard, convential REST and Daylight supported actions.
#
# Have your API Controllers subclass from APIController:
#
#   class ExampleController < APIController
#   end
#
# You must "turn on" common actions to allow for functionality.  All common
# actions are turned off by default so that what is exposed is
# determiend by the API devloper.  For example, to turn on `index` action:
#
#   class ExampleController < APIController
#     handles :index
#   end
#
# The common actions provided by APIController are: `:index`, `:create`,
# `:show`, `:update`, `:destroy`, `:associated`, and `:remoted`.
#
# The method implementations are simply methods in a superclass and can be
# overwritten or called through `super`:
#
#   class ExampleController < APIController
#     handles :index
#
#     def index
#        @title = 'My Title'
#        super
#     end
#   end
#
# The model and instance variable for these actions are based on the
# controller name.  If you need to customize these, you can change them:
#
#   class ExampleController < APIController
#     self.model_name  = :news
#     self.record_name = :post
#
#     handles :index
#   end
#
# Continue to use `ApplicationController` for shared methods.
#
# See:
# ApplicationController

class Daylight::APIController < ApplicationController
  include Daylight::Helpers
  include VersionedUrlFor

  API_ACTIONS = [:index, :create, :show, :update, :destroy, :associated, :remoted].freeze
  class_attribute :record_name, :model_name

  ##
  # Ensure messaging when sending unknown attributes or improper SQL
  rescue_from ArgumentError,
              ActiveRecord::UnknownAttributeError,
              ActiveRecord::StatementInvalid do |e|

    render json: { errors: e.message }, status: :bad_request
  end

  ##
  # Ensure messaging when there are validation errors on save and update
  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { errors: e.record.errors }, status: :unprocessable_entity
  end

  class << self
    protected
      ##
      # Turns on common actions based on subclass needs (sets them as public methods).
      # Uses whitelist of allowed actions to be handled.
      #
      # See:
      # API_ACTIONS
      #--
      # `public` is called in context of the subclass
      def handles *actions
        whitelisted = actions.map(&:to_sym) & API_ACTIONS
        whitelisted = API_ACTIONS.dup if actions.any? {|a| a == :all }

        if (unhandled = actions - whitelisted).present?
          logger.warn "Daylight::APIController isn't handling the following unwhitelisted actions:"
          logger.warn "\t#{unhandled.join(',')}"
        end

        public *whitelisted if whitelisted.present?
      end

      ##
      # Retrieves conventional key for a model name used in params
      def model_key
        model_name.to_s.singularize.to_sym
      end

      ##
      # Retieves `const` for ActiveRecord model as defined by `model_name`
      def model
        model_name.to_s.classify.constantize
      end

      ##
      # Delegates to `model#primary_key`
      # Not using delegate as model may change via `model_name` configuration
      def primary_key
        model.primary_key
      end

      ##
      # Sets the default `model_name` and `record_name` by default.
      # By default, they are based on the value determined by `controller_name`
      #
      # See:
      # ActionController::Base.controller_name
      def inherited api
        api.model_name  = api.controller_name
        api.record_name = api.controller_name
      rescue => e
        logger.warn "Bypassing default configuration on Daylight::APIController"
        logger.warn "\t#{e.name}: #{e.message}"

        # for testing, call `inherited` manually
      end
  end

  protected
    ##
    # Retrieves the value for the `record_name` instance variable
    def record
      instance_variable_get("@#{record_name}")
    end

    ##
    # Sets the value for the `record_name` instance variable
    def record= value
      instance_variable_set("@#{record_name}", value)
    end

    ##
    # Instance-level delegate of the `model` method
    #
    # See:
    # #model
    def model
      self.class.send(:model)
    end

    ##
    # Instance-level delegate of the `model_key` method
    #
    # See:
    # #model_key
    def model_key
      self.class.send(:model_key)
    end

    ##
    # Instance-level delegate of the `primary_key` method
    #
    # See:
    # #primary_key
    def primary_key
      self.class.send(:primary_key)
    end
  private
    #
    # The common actions for Daylight::APIController
    #

    ##
    # Retrieves the collection for the records for `model` with any refinements
    # in the params passed to `refine_by`.  Accessed via:
    #
    #   GET /posts.json
    #
    # Subclass implementation:
    #
    #   def index
    #     render json: Post.refine_by(params)
    #   end
    #
    # See:
    # Daylight::Refiners.refine_by
    def index
      render json: model.refine_by(params)
    end

    ##
    # Creates a record for the `model` with the attributes supplied in params.
    # Accessed via:
    #
    #   POST /posts.json
    #
    # Subclass implementation:
    #
    #   def create
    #     @post = Post.new(params[:post])
    #     @post.save!
    #
    #     render json: @post, status: :created, location: @post
    #   end
    def create
      record = model.new(params[model_key])
      record.save!

      render json: record, status: :created, location: record
    end

    ##
    # Retrieves a record for the `model` with the `id` supplied in params.
    # If the primary_key is configured to something besides `id` it will
    # use that as a key.
    #
    # Accessed via:
    #
    #   GET /posts/1.json
    #
    # Subclass implementation:
    #
    #   def show
    #     render json: Post.find(params[Post.primary_key])
    #   end
    def show
      render json: model.find(params[primary_key])
    end

    ##
    # Updates a record for the `model` with the `id` supplied in params.
    # If the primary_key is configured to something besides `id` it will
    # use that as a key.
    #
    # Accessed via:
    #
    #   PATCH/PUT /posts/1.json
    #
    # Subclass implementation:
    #
    #   def update
    #     Post.find(params[Post.primary_key]).update!(params[:post])
    #
    #     head :no_content
    #   end
    def update
      model.find(params[primary_key]).update!(params[model_key])

      head :no_content
    end

    ##
    # Destroys a record for the `model` with the `id` supplied in params.
    # If the primary_key is configured to something besides `id` it will
    # use that as a key.
    #
    # Accessed via:
    #
    #   DELETE /posts/1.json
    #
    # Subclass implementation:
    #
    #   def destroy
    #     Post.find(params[Post.primary_key]).destroy
    #
    #     head :no_content
    #   end
    def destroy
      model.find(params[primary_key]).destroy

      head :no_content
    end

    ##
    # Retrieves the collection for the associated records for a `model` with
    # any refinements in the params passed to `associated`.  Accessed via:
    #
    #   GET /posts/1/comments.json
    #
    # Subclass implementation:
    #
    #   def associated
    #     render json: Post.associated(params), root: associated_params
    #   end
    #
    # See:
    # Daylight::Refiners.associated
    # Daylight::Helpers.associated_params
    # RouteOptions
    def associated
      render json: model.associated(params), root: associated_params
    end

    ##
    # Retrieves the collection for the associated records for a `model` with
    # any refinements in the params passed to `associated`.  Accessed via:
    #
    #   GET /posts/1/all_authorized_users.json
    #
    # Subclass implementation:
    #
    #   def remoted
    #     render json: Post.remoted(params), root: remoted_params
    #   end
    #
    # See:
    # Daylight::Refiners.remoted
    # Daylight::Helpers.remoted_params
    # RouteOptions
    def remoted
      render json: model.remoted(params), root: remoted_params
    end
end