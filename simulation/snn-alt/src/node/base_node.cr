require "../event"
require "../route"

abstract class Node(P, R)

  def initialize()
  end

  abstract def process(event : Event(P)) : R
end
