class Conversation < ActiveRecord::Base

  has_many :messages, :dependent => :destroy

  has_many :participations, :dependent => :destroy
  has_many :participants, :through => :participations, :source => :person
  belongs_to :community

  def self.unread_count(person_id)
    user = Person.find_by_id(person_id)
    new_value = user.participations.select do |particiation|
      !particiation.is_read || particiation.conversation.should_notify?(user)
    end.count
  end

  # Creates a new message to the conversation
  def message_attributes=(attributes)
    messages.build(attributes)
  end

  # Sets the participants of the conversation
  def conversation_participants=(conversation_participants)
    conversation_participants.each do |participant, is_sender|
      last_at = is_sender.eql?("true") ? "last_sent_at" : "last_received_at"
      participations.build(:person_id => participant,
                           :is_read => is_sender,
                           :is_starter => is_sender,
                           last_at.to_sym => DateTime.now)
    end
  end

  # If this method returns true, user should be notified about this conversation
  # even if the conversation is read by the user
  def should_notify?(*)
    false
  end

  # Returns last received or sent message
  def last_message
    return messages.last
  end

  def other_party(person)
    participants.reject { |p| p.id == person.id }.first
  end

  def read_by?(person)
    participations.where(["person_id LIKE ?", person.id]).first.is_read
  end

  # Send email notification to message receivers and returns the receivers
  def send_email_to_participants(community)
    recipients(messages.last.sender).each do |recipient|
      if recipient.should_receive?("email_about_new_messages")
        PersonMailer.new_message_notification(messages.last, community).deliver
      end
    end
  end

  # Returns all the participants except the message sender
  def recipients(sender)
    participants.reject { |p| p.id == sender.id }
  end

  def update_is_read(current_user)
    # TODO
    # What does this actually do? What happens if requester.eql? current_user?
    if offerer.eql?(current_user)
      participations.each { |p| p.update_attribute(:is_read, p.person.id.eql?(current_user.id)) }
    end
  end

  def starter
    participations.find { |p| p.is_starter? }.person
  end
end
