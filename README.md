The repository contains a Python file that creates a server socket and a MQL5 file that creates a client socket. 
Both can send and receive data. The Python code is implemented using the native socket and threading packages.
The MQL5 code is implemented using the socketlib.mqh file. The .mqh file imports the windows library for working
with sockets: Ws2_32.dll. A explanation for the .mqh file can be found here: https://www.mql5.com/en/articles/2599
Some adjustments where made following a recommendation from this thread: https://www.mql5.com/en/forum/91815
