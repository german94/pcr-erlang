-module(fibonacci_pcr).

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

identity_lambda() ->
    fun(X) -> X end.

generate_fib_even_counter_pcr() ->
    Reducer = #reducer{node_logic=sum_lambda(), initial_val=0},
    #pcr{producer=fib_lambda(), consumers=[even_lambda()], reducer=Reducer}.