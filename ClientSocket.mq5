#include "/socketlib.mqh"

#define SERVER_IP_ADDRESS "127.0.0.1"
#define SERVER_PORT 8888

SOCKET64 client = INVALID_SOCKET64;

int OnInit(){
   OnTick(); // create socket immediately
   
   return(INIT_SUCCEEDED); 
} 

void OnDeinit(const int reason){
   CloseClean();
} 

void OnTick(){
   if(client != INVALID_SOCKET64){
      uchar data[]; 
      StringToCharArray(_Symbol+" "+DoubleToString(SymbolInfoDouble(Symbol(),SYMBOL_BID),_Digits),data);
      if(send(client,data,ArraySize(data)-1,0) == SOCKET_ERROR){
         int err = WSAGetLastError();
         if(err != WSAEWOULDBLOCK){ 
            Print(__FUNCTION__," > send failed error: "+WSAErrorDescript(err)); 
            CloseClean(); 
         }
      }else{
         Print(__FUNCTION__,"> send "+_Symbol+" tick to server");
      }

      char buf[1024];
      if(recv(client,buf,ArraySize(buf),0) == SOCKET_ERROR){
         int err = WSAGetLastError();
         if(err != WSAEWOULDBLOCK){ 
            Print(__FUNCTION__," > recv failed error: "+WSAErrorDescript(err)); 
            CloseClean(); 
         }
      }else{
         Print(__FUNCTION__,"> [INFO]\tMessage: ",CharArrayToString(buf));
      }
   }else{
      char wsaData[]; ArrayResize(wsaData,sizeof(WSAData));
      int res = WSAStartup(MAKEWORD(2,2),wsaData);
      if(res != 0){
         Print(__FUNCTION__," > WSAStartup failed error: "+string(res));
         return; 
      }

      // create a socket
      client = socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
      if(client == INVALID_SOCKET64){ 
         Print(__FUNCTION__," > socket failed error: "+WSAErrorDescript(WSAGetLastError()));
         CloseClean();
         return; 
      }

      //connect to server
      char ch[]; 
      StringToCharArray(SERVER_IP_ADDRESS,ch);
      sockaddr_in addrin;
      addrin.sin_family = AF_INET;
      addrin.sin_addr = inet_addr(ch);
      addrin.sin_port = htons(SERVER_PORT);
      ref_sockaddr ref;
      sockaddrIn2RefSockaddr(addrin,ref);

      res = connect(client,ref.ref,sizeof(addrin));
      if(res == SOCKET_ERROR){
         int err = WSAGetLastError();
         if(err != WSAEISCONN){
            Print(__FUNCTION__," > connect failed error: "+WSAErrorDescript(err)); 
            CloseClean(); 
            return; 
         }
      }

      // set to nonblocking mode
      int non_block=1;
      res = ioctlsocket(client,(int)FIONBIO,non_block);
      if(res != NO_ERROR){
         Print(__FUNCTION__," > ioctlsocket failed error: "+string(res)); 
         CloseClean(); 
         return; 
      }

      Print(__FUNCTION__," > socket created...");
   }
}

void CloseClean(){
   if(client != INVALID_SOCKET64){
      closesocket(client);
      client = INVALID_SOCKET64;
   }
   WSACleanup();
   Print(__FUNCTION__," > socket closed...");
}