-module(fib_primes_pcr).
-export([generate_pcr/0, not_divisor/0]).

fib_lambda() ->
    fun F(0) -> 0; F(1) -> 1; F(X) -> F(X - 1) + F(X - 2) end.

count_primes() ->
    fun F(X, true) -> X + 1; F(X, _) -> X end.

identity() ->
    fun(X) -> X end.

not_divisor() ->
    fun F(X, X) -> true; 
        F(X, 1) -> true;
        F(X, Y) -> not (X rem Y == 0) end.

and_fun() ->
    fun(X, Y) -> X and Y end.

generate_is_prime_pcr() ->
    PossibleDivisorsProducer = pcr_components:create_producer(producer, identity()),
    NotDivisorCheck = pcr_components:create_consumer(divisor, [producer], not_divisor()),
    PrimeCheckReducer = pcr_components:create_reducer(count_divisors, [divisor], and_fun(), true),
    pcr_components:create_pcr(PossibleDivisorsProducer, [NotDivisorCheck], PrimeCheckReducer).

generate_pcr() ->
    Producer = pcr_components:create_producer(producer, fib_lambda()),
    IsPrimeConsumer = pcr_components:create_consumer(is_prime, [pcr_input, producer], generate_is_prime_pcr()),
    Reducer = pcr_components:create_reducer(count, [is_prime], count_primes(), 0),
    Pcr = pcr_components:create_pcr(Producer, [IsPrimeConsumer], Reducer),
    pcr_init:start_pcr(Pcr, [self()]).