# pcr-erlang
PCR pattern implementation in Erlang programming language

### How to run it
- Download Erlang from: https://www.erlang.org/
<<<<<<< HEAD
- Open a terminal in the root directory and run ```erl -make``` in order to compile the project
- ```cd ebin; erl```
- ```l(fibonacci_pcr). l(pcr_utils).``` (you can also load sum_pows_pcr instead of fibonacci_pcr)
=======
- Open a terminal in the project's root directory and run ```erl -make``` in order to compile the project
- ```cd ebin; erl```
- ```l(fibonacci_pcr). l(pcr_utils).``` (you can also load sum_pows_pcr instead of fibonacci_pcr depending on the example you want to run)
>>>>>>> d4b50fff3c21630ecd6811e06164724ed75a42f3
- Generate a test PCR: ``` Pcr = fibonacci_pcr:generate_pcr().``` or ``` Pcr = sum_pows_pcr:generate_pcr().``` depending on what you loaded
- Send an input to the PCR (in this case the input is 5): ``` pcr_utils:send_input_to_pcr(5, Pcr).```
- Flush the process mailbox in order to see the PCR output for the input that has been sent: ``` flush().```
- You should be able to see something like: ``` Shell got {pcr_output,2} ```, which is the output that the current process (the shell) received from the PCR.
