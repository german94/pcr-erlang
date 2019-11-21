-module(pcr_nodes).
-record(active_node, {id, pid}).
-export([create_node/2, get_node_id/1, get_node_pid/1]).

create_node(Id, Pid) ->
    #active_node{id=Id, pid=Pid}.

get_node_id(Node) ->
    Node#active_node.id.

get_node_pid(Node) ->
    Node#active_node.pid.