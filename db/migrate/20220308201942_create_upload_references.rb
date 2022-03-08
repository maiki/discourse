# frozen_string_literal: true

class CreateUploadReferences < ActiveRecord::Migration[6.1]
  def change
    create_table :upload_references do |t|
      t.references :upload
      t.references :target, polymorphic: true
    end
  end
end
