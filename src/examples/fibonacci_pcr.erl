-module(fibonacci_pcr).
-export([generate_pcr/0]).

%Functions to generate PCRs for testing
even_lambda() ->
    fun(X) ->
        if
            X rem 2 == 0 -> 1;
            true -> 0
        end
    end.

fib_lambda() ->
    fun F(0) -> 0; F(1) -> 1; F(X) -> F(X - 1) + F(X - 2) end.

sum_lambda() ->
    fun(X, Y) -> X + Y end.

generate_pcr() ->
    Producer = pcr_components:create_producer(producer, fib_lambda()),
    Consumer = pcr_components:create_consumer(even_filter, [producer], even_lambda()),
    Reducer = pcr_components:create_reducer(sum, [even_filter], sum_lambda(), 0),
    Pcr = pcr_components:create_pcr(Producer, [Consumer], Reducer),
    pcr_init:start_pcr(Pcr, [self()]).