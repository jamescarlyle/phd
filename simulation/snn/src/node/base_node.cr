require "../event"
require "../route"

abstract class Node(P, R)
  getter node_id : UInt32
  getter routes : Array(Route)

  def initialize(@node_id : UInt32)
    @routes = Array(Route).new
  end

  def add_route(route : Route) : Nil
    @routes << route
  end

  abstract def process(event : Event(P)) : R
end
