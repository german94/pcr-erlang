-module(sum_pows_pcr).
-export([generate_pcr/0]).

identity_lambda() ->
    fun(X) -> X end.

sum_lambda() ->
    fun(X, Y) -> X + Y end.

pow2_lambda() ->
    fun(X) -> X * X end.

pow3_lambda() ->
    fun(X) -> X * X * X end.

make_list_lambda() ->
    fun(X, Y) -> [X|Y] end.

generate_pcr() ->
    Producer = pcr_components:create_producer(producer, identity_lambda()),
    ConsumerPow2 = pcr_components:create_consumer(pow2, [producer], pow2_lambda()),
    ConsumerPow3 = pcr_components:create_consumer(pow3, [producer], pow3_lambda()),
    ConsumerSum = pcr_components:create_consumer(sum, [pow2, pow3], sum_lambda()),
    Reducer = pcr_components:create_reducer(make_list, [sum], make_list_lambda(), []),
    Pcr = pcr_components:create_pcr(Producer, [ConsumerPow2, ConsumerPow3, ConsumerSum], Reducer),
    pcr_init:start_pcr(Pcr, [self()]).