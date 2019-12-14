-module(pcr_utils).
-export([
    apply_fun/3, 
    stop_pcr/1, 
    notify_new_item/2,
    get_producer_listeners/2,
    send_message_to_node/2,
    broadcast_to_nodes/2,
    send_each_node_its_listeners/2,
    generate_uuid/0
]).

apply_fun(Fun, [], Inputs) ->
    apply(Fun, Inputs);
apply_fun(Fun, [Source|Sources], Inputs) ->
    InputOfSource = element(2, lists:keyfind(Source, 1, Inputs)),
    apply_fun(Fun, Sources, [InputOfSource|lists:keydelete(Source, 1, Inputs)]).

stop_pcr(OutputLoopPid) ->
    OutputLoopPid ! stop.

notify_new_item(OutputLoopPid, Token) ->
    OutputLoopPid ! {new_item, Token}.

get_producer_listeners(Pcr, Listeners) ->
    ProducerId = pcr_components:get_id(pcr_components:get_producer(Pcr)),
    ProducerListenersIds = [pcr_components:get_id(Component) || Component <- pcr_components:get_listeners_of_id(ProducerId, Pcr)],
    [Listener || Listener <- Listeners, lists:member(pcr_nodes:get_node_id(Listener), ProducerListenersIds)].

send_message_to_node(Message, Node) ->
    pcr_nodes:get_node_pid(Node) ! Message.

broadcast_to_nodes(Message, Nodes) ->
    lists:foreach(fun(Node) -> send_message_to_node(Message, Node) end, Nodes).

send_each_node_its_listeners(Pcr, Listeners) ->
    SendListenersToNode = fun(Node) -> 
        NodeId = pcr_nodes:get_node_id(Node),
        ListenersIds = [pcr_components:get_id(Listener) || Listener <- pcr_components:get_listeners_of_id(NodeId, Pcr)],
        ListenersNodes = [Listener || Listener <- Listeners, lists:member(pcr_nodes:get_node_id(Listener), ListenersIds)],
        erlang:display({sending_listeners_to_node, NodeId, ListenersNodes}),
        send_message_to_node({listeners, ListenersNodes}, Node) 
    end,
    lists:foreach(SendListenersToNode, Listeners).

%Generates a new token with a length of 20 characters
generate_uuid() ->
    base64:encode(crypto:strong_rand_bytes(20)).