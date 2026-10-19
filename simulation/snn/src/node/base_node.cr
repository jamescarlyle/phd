require "../event"
require "../route"

abstract class Node(P, R)
  getter node_id
  getter source_routes
  getter target_routes

  def initialize(@node_id : UInt32)
    @source_routes = Array(SourceRoute).new
    @target_routes = Array(TargetRoute).new
  end

  def add_source_route(route : SourceRoute) : Nil
    @source_routes << route
  end

  def add_target_route(route : TargetRoute) : Nil
    @target_routes << route
  end

  abstract def process(event : Event(P)) : R
end
