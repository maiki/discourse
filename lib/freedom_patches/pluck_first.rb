# frozen_string_literal: true

class ActiveRecord::Relation
  def pluck_first(*attributes)
    limit(1).pluck(*attributes).first
  end

  def pluck_first!(*attributes)
    pluck_first.presence || raise_record_not_found_exception
  end
end

ActiveRecord::Querying.delegate(:pluck_first, :pluck_first!, to: :all)
