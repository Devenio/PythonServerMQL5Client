#include "/socketlib.mqh";
#include <Trade/Trade.mqh>;
#include <JAson.mqh>;

#define SERVER_IP_ADDRESS "127.0.0.1"
#define SERVER_PORT 8888

// Expert status constants
#define STATUS_DISCONNECTED   0
#define STATUS_CONNECTING     1
#define STATUS_CONNECTED      2
#define STATUS_LISTENING      3
#define STATUS_ERROR         -1
#define STATUS_RECONNECTING  -2

// Global variables
SOCKET64 client = INVALID_SOCKET64;
int expertStatus = STATUS_DISCONNECTED;
datetime lastConnectionAttempt = 0;
int reconnectDelay = 5; // Seconds between reconnection attempts
CTrade trade;
CJAVal json;

// Forward declarations
string HandleQuery(string query);
string GetAccountInfo();
string GetOpenPositions();
string GetPendingOrders();
string GetTradeHistory();
void ProcessSocketError(string functionName, int errorCode);

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit(){
   expertStatus = STATUS_CONNECTING;
   ConnectSocket(); 
   return(INIT_SUCCEEDED); 
} 

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
   CloseClean();
} 

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick(){
   // Handle reconnection if needed
   if(expertStatus == STATUS_DISCONNECTED || expertStatus == STATUS_ERROR){
      if(int(TimeCurrent() - lastConnectionAttempt) >= reconnectDelay){
         Print("Attempting to reconnect...");
         expertStatus = STATUS_RECONNECTING;
         ConnectSocket();
      }
      return;
   }
   
   // Handle incoming queries
   if(IsSocketConnected()){
      expertStatus = STATUS_LISTENING;
      char buffer[1024];
      int bytesRead = recv(client, buffer, ArraySize(buffer), 0);
      
      if(bytesRead == SOCKET_ERROR){
         int err = WSAGetLastError();
         if(err != WSAEWOULDBLOCK){
            ProcessSocketError(__FUNCTION__, err);
            return;
         }
      }
      else if(bytesRead > 0){
         string query = CharArrayToString(buffer);
         Print("Received query: ", query);
         string response = HandleQuery(query);
         Print("Sending response: ", response);

         // Send response
         if(response != ""){
            uchar responseData[];
            StringToCharArray(response, responseData);
            if(send(client, responseData, ArraySize(responseData)-1, 0) == SOCKET_ERROR){
               ProcessSocketError(__FUNCTION__, WSAGetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Socket connection function                                         |
//+------------------------------------------------------------------+
void ConnectSocket(){
   if(client == INVALID_SOCKET64){
      lastConnectionAttempt = TimeCurrent();
      
      char wsaData[]; ArrayResize(wsaData,sizeof(WSAData));
      int res = WSAStartup(MAKEWORD(2,2),wsaData);
      if(res != 0){
         ProcessSocketError(__FUNCTION__, res);
         return; 
      }

      client = socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
      if(client == INVALID_SOCKET64){ 
         ProcessSocketError(__FUNCTION__, WSAGetLastError());
         return; 
      }

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
            ProcessSocketError(__FUNCTION__, err);
            return; 
         }
      }

      int non_block=1;
      res = ioctlsocket(client,(int)FIONBIO,non_block);
      if(res != NO_ERROR){
         ProcessSocketError(__FUNCTION__, res);
         return; 
      }

      expertStatus = STATUS_CONNECTED;
      Print(__FUNCTION__," > socket created and connected successfully");
   }
}

//+------------------------------------------------------------------+
//| Clean socket closure function                                      |
//+------------------------------------------------------------------+
void CloseClean(){
   if(client != INVALID_SOCKET64){
      closesocket(client);
      client = INVALID_SOCKET64;
   }
   WSACleanup();
   expertStatus = STATUS_DISCONNECTED;
   Print(__FUNCTION__," > socket closed...");
}

//+------------------------------------------------------------------+
//| Query handler function                                             |
//+------------------------------------------------------------------+
string HandleQuery(string query){
   if(!json.Deserialize(query)) return CreateErrorResponse("Invalid JSON format");
   
   string cmd = json["cmd"].ToStr();
   
   if(cmd == "ACCOUNT")
      return GetAccountInfo();
   else if(cmd == "POSITIONS")
      return GetOpenPositions();
   else if(cmd == "PENDING")
      return GetPendingOrders();
   else if(cmd == "HISTORY")
      return GetTradeHistory();
   else if(cmd == "STATUS")
      return GetExpertStatus();
   
   return CreateErrorResponse("Unknown command: " + cmd);
}

//+------------------------------------------------------------------+
//| Account information function                                       |
//+------------------------------------------------------------------+
string GetAccountInfo(){
   CJAVal response;
   response["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   response["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
   response["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
   response["freeMargin"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   response["profit"] = AccountInfoDouble(ACCOUNT_PROFIT);
   response["currency"] = AccountInfoString(ACCOUNT_CURRENCY);
   response["leverage"] = AccountInfoInteger(ACCOUNT_LEVERAGE);
   response["name"] = AccountInfoString(ACCOUNT_NAME);
   response["server"] = AccountInfoString(ACCOUNT_SERVER);
   response["company"] = AccountInfoString(ACCOUNT_COMPANY);
   
   return response.Serialize();
}

//+------------------------------------------------------------------+
//| Open positions function                                            |
//+------------------------------------------------------------------+
string GetOpenPositions(){
   CJAVal response;
   response["positions"] = CJAVal(true);
   
   for(int i = 0; i < PositionsTotal(); i++){
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      CJAVal position;
      position["ticket"] = int(ticket);
      position["symbol"] = PositionGetString(POSITION_SYMBOL);
      position["type"] = PositionGetInteger(POSITION_TYPE);
      position["volume"] = PositionGetDouble(POSITION_VOLUME);
      position["openPrice"] = PositionGetDouble(POSITION_PRICE_OPEN);
      position["currentPrice"] = PositionGetDouble(POSITION_PRICE_CURRENT);
      position["sl"] = PositionGetDouble(POSITION_SL);
      position["tp"] = PositionGetDouble(POSITION_TP);
      position["profit"] = PositionGetDouble(POSITION_PROFIT);
      position["swap"] = PositionGetDouble(POSITION_SWAP);
      position["comment"] = PositionGetString(POSITION_COMMENT);
      
      response["positions"].Add(position);
   }
   
   return response.Serialize();
}

//+------------------------------------------------------------------+
//| Pending orders function                                           |
//+------------------------------------------------------------------+
string GetPendingOrders(){
   CJAVal response;
   response["orders"] = CJAVal(true);
   
   for(int i = 0; i < OrdersTotal(); i++){
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      
      CJAVal order;
      order["ticket"] = int(ticket);
      order["symbol"] = OrderGetString(ORDER_SYMBOL);
      order["type"] = OrderGetInteger(ORDER_TYPE);
      order["volume"] = OrderGetDouble(ORDER_VOLUME_INITIAL);
      order["openPrice"] = OrderGetDouble(ORDER_PRICE_OPEN);
      order["stopLoss"] = OrderGetDouble(ORDER_SL);
      order["takeProfit"] = OrderGetDouble(ORDER_TP);
      order["comment"] = OrderGetString(ORDER_COMMENT);
      
      response["orders"].Add(order);
   }
   
   return response.Serialize();
}

//+------------------------------------------------------------------+
//| Trade history function                                            |
//+------------------------------------------------------------------+
string GetTradeHistory(){
   CJAVal response;
   response["history"] = CJAVal(true);
   
   HistorySelect(0, TimeCurrent()); // Select all history
   
   for(int i = 0; i < HistoryDealsTotal(); i++){
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;
      
      CJAVal deal;
      deal["ticket"] = int(ticket);
      deal["symbol"] = HistoryDealGetString(ticket, DEAL_SYMBOL);
      deal["type"] = HistoryDealGetInteger(ticket, DEAL_TYPE);
      deal["entry"] = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      deal["volume"] = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      deal["price"] = HistoryDealGetDouble(ticket, DEAL_PRICE);
      deal["profit"] = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      deal["commission"] = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      deal["swap"] = HistoryDealGetDouble(ticket, DEAL_SWAP);
      deal["time"] = TimeToString((datetime)HistoryDealGetInteger(ticket, DEAL_TIME));
      
      response["history"].Add(deal);
   }
   
   return response.Serialize();
}

//+------------------------------------------------------------------+
//| Expert status function                                            |
//+------------------------------------------------------------------+
string GetExpertStatus(){
   CJAVal response;
   
   string status = "unknown";
   switch(expertStatus){
      case STATUS_DISCONNECTED: status = "disconnected"; break;
      case STATUS_CONNECTING: status = "connecting"; break;
      case STATUS_CONNECTED: status = "connected"; break;
      case STATUS_LISTENING: status = "listening"; break;
      case STATUS_ERROR: status = "error"; break;
      case STATUS_RECONNECTING: status = "reconnecting"; break;
   }
   
   response["status"] = status;
   response["lastConnectionAttempt"] = TimeToString(lastConnectionAttempt);
   response["uptime"] = TimeToString(TimeCurrent() - lastConnectionAttempt);
   
   return response.Serialize();
}

//+------------------------------------------------------------------+
//| Error handling function                                           |
//+------------------------------------------------------------------+
void ProcessSocketError(string functionName, int errorCode){
   expertStatus = STATUS_ERROR;
   Print(functionName, " > Error: ", WSAErrorDescript(errorCode));
   CloseClean();
}

//+------------------------------------------------------------------+
//| Error response creator function                                    |
//+------------------------------------------------------------------+
string CreateErrorResponse(string message){
   CJAVal response;
   response["error"] = message;
   return response.Serialize();
}

//+------------------------------------------------------------------+
//| Socket connection check function                                   |
//+------------------------------------------------------------------+
bool IsSocketConnected(){
   return client != INVALID_SOCKET64;
} 