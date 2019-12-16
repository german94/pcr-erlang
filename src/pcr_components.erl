-module(pcr_components).
-record(consumer, {id, sources, node_logic}).
-record(producer, {id, node_logic}).
-record(reducer, {id, sources, node_logic, initial_val}).
-record(pcr, {producer, consumers, reducer}).
-export([
    get_reducer_initial_value/1, 
    get_reducer_id/1,
    get_consumers/1,
    get_producer/1,
    get_reducer/1,
    get_listeners_of_id/2,
    get_id/1,
    get_sources/1,
    get_fun/1,
    create_producer/2,
    create_consumer/3,
    create_reducer/4,
    create_pcr/3,
    is_consumer/1,
    is_producer/1,
    is_reducer/1
]).

get_reducer_initial_value(Reducer) ->
    Reducer#reducer.initial_val.

get_reducer_id(Node) ->
    if
        is_record(Node, reducer) -> Node#reducer.id;
        true -> get_reducer_id(get_reducer(Node))
    end.

create_consumer(Id, Sources, NodeLogic) ->
    #consumer{id=Id, sources=Sources, node_logic=NodeLogic}.

create_producer(Id, NodeLogic) ->
    #producer{id=Id, node_logic=NodeLogic}.

create_reducer(Id, Sources, NodeLogic, InitVal) ->
    #reducer{id=Id, sources=Sources, node_logic=NodeLogic, initial_val=InitVal}.

create_pcr(Producer, Consumers, Reducer) ->
    #pcr{producer=Producer, consumers=Consumers, reducer=Reducer}.

get_consumers(Pcr) ->
    Pcr#pcr.consumers.

get_producer(Pcr) ->
    Pcr#pcr.producer.

get_reducer(Pcr) ->
    Pcr#pcr.reducer.

get_listeners_of_id(Id, Pcr) ->
    [Component || Component <- [get_reducer(Pcr)|get_consumers(Pcr)], lists:member(Id, get_sources(Component))].

is_producer(Component) when element(1, Component) == producer -> true;
is_producer(_) -> false.

is_consumer(Component) when element(1, Component) == consumer -> true;
is_consumer(_) -> false.

is_reducer(Component) when element(1, Component) == reducer -> true;
is_reducer(_) -> false.

get_id(Component) when element(1, Component) == consumer -> Component#consumer.id;
get_id(Component) when element(1, Component) == producer -> Component#producer.id;
get_id(Component) when element(1, Component) == reducer -> Component#reducer.id.

get_sources(Component) when element(1, Component) == producer -> [];
get_sources(Component) when element(1, Component) == consumer -> Component#consumer.sources;
get_sources(Component) when element(1, Component) == reducer -> Component#reducer.sources.

get_fun(Component) when element(1, Component) == consumer -> Component#consumer.node_logic;
get_fun(Component) when element(1, Component) == producer -> Component#producer.node_logic;
get_fun(Component) when element(1, Component) == reducer -> Component#reducer.node_logic.
