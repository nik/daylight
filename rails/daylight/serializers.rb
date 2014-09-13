module Daylight::Serializers

  ##
  # Define a fallback serializer

  def active_model_serializer
    super || auto_generate_serializer
  end

  private

    def auto_generate_serializer
      model_class = self.class
      @auto_generated_serializer ||=
        Class.new(ActiveModel::Serializer) do
          embed :ids
          attributes(*model_class.column_names.map(&:to_sym))
          model_class.reflections.each_pair do |name, reflection|
            case reflection.macro
            when :has_one, :belongs_to
              has_one name, reflection.options.slice(:through)
            end
          end
        end
    end

end

# Mix into ActiveRecord::Base
ActiveSupport.on_load :active_record do
  include Daylight::Serializers
end
