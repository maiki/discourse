# frozen_string_literal: true

class TopicConverter

  attr_reader :topic

  def initialize(topic, user)
    @topic = topic
    @user = user
  end

  def convert_to_public_topic(category_id = nil)
    Topic.transaction do
      category_id =
        if category_id
          category_id
        elsif SiteSetting.allow_uncategorized_topics
          SiteSetting.uncategorized_category_id
        else
          Category.where(read_restricted: false)
            .where.not(id: SiteSetting.uncategorized_category_id)
            .order('id asc')
            .pluck_first(:id)
        end

      PostRevisor.new(@topic.first_post, @topic).revise!(
        @user,
        category_id: category_id,
        archetype: Archetype.default
      )

      update_user_stats
      update_post_uploads_secure_status
      Jobs.enqueue(:topic_action_converter, topic_id: @topic.id)
      Jobs.enqueue(:delete_inaccessible_notifications, topic_id: @topic.id)
      watch_topic(topic)
    end
    @topic
  end

  def convert_to_private_message
    Topic.transaction do
      @topic.update_category_topic_count_by(-1) if @topic.visible

      PostRevisor.new(@topic.first_post, @topic).revise!(
        @user,
        category_id: nil,
        archetype: Archetype.private_message
      )

      add_allowed_users
      update_post_uploads_secure_status
      UserProfile.remove_featured_topic_from_all_profiles(@topic)

      Jobs.enqueue(:topic_action_converter, topic_id: @topic.id)
      Jobs.enqueue(:delete_inaccessible_notifications, topic_id: @topic.id)

      watch_topic(topic)
    end
    @topic
  end

  private

  def posters
    @posters ||= @topic.posts.where("post_number > 1").distinct.pluck(:user_id)
  end

  def increment_users_post_count
    update_users_post_count(:increment)
  end

  def decrement_users_post_count
    update_users_post_count(:decrement)
  end

  def update_users_post_count(action)
    operation = action == :increment ? "+" : "-"

    # NOTE that DirectoryItem.refresh will overwrite this by counting UserAction records.
    #
    # Changes user_stats (post_count) by the number of posts in the topic.
    # First post, hidden posts and non-regular posts are ignored.
    DB.exec(<<~SQL)
    UPDATE user_stats
    SET post_count = post_count #{operation} X.count
    FROM (
      SELECT
        us.user_id,
        COUNT(*) AS count
      FROM user_stats us
      INNER JOIN posts ON posts.topic_id = #{@topic.id.to_i} AND posts.user_id = us.user_id
      WHERE posts.post_number > 1
      AND NOT posts.hidden
      AND posts.post_type = #{Post.types[:regular].to_i}
      GROUP BY us.user_id
    ) X
    WHERE X.user_id = user_stats.user_id
    SQL
  end

  def update_user_stats
    increment_users_post_count
    UserStatCountUpdater.increment!(@topic.first_post)
  end

  def add_allowed_users
    decrement_users_post_count
    UserStatCountUpdater.decrement!(@topic.first_post)

    existing_allowed_users = @topic.topic_allowed_users.pluck(:user_id)
    users_to_allow = posters << @user.id

    if (users_to_allow | existing_allowed_users).length > SiteSetting.max_allowed_message_recipients
      users_to_allow = [@user.id]
    end

    (users_to_allow - existing_allowed_users).uniq.each do |user_id|
      @topic.topic_allowed_users.build(user_id: user_id)
    end

    @topic.save!
  end

  def watch_topic(topic)
    @topic.notifier.watch_topic!(topic.user_id)

    @topic.reload.topic_allowed_users.each do |tau|
      next if tau.user_id < 0 || tau.user_id == topic.user_id
      topic.notifier.watch!(tau.user_id)
    end
  end

  def update_post_uploads_secure_status
    DB.after_commit do
      Jobs.enqueue(:update_topic_upload_security, topic_id: @topic.id)
    end
  end
end
