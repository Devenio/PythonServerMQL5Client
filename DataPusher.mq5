#include "/socketlib.mqh"
#include <Trade/Trade.mqh>
#include <JAson.mqh>

// --add-host=host.docker.internal:host-gateway (in linux or --network host)
#define SERVER_IP_ADDRESS "127.0.0.1"
#define SERVER_PORT 8888

// Expert status constants
#define STATUS_DISCONNECTED   0
#define STATUS_CONNECTING     1
#define STATUS_CONNECTED      2
#define STATUS_ERROR         -1
#define STATUS_RECONNECTING  -2

// Global variables  
SOCKET64 client = INVALID_SOCKET64;
int expertStatus = STATUS_DISCONNECTED;
datetime lastConnectionAttempt = 0;
int reconnectDelay = 5; // Seconds between reconnection attempts
CTrade trade;
CJAVal json;

// Tracking variables
double lastEquity = 0;
int lastPositionsTotal = 0;
int lastOrdersTotal = 0;
datetime lastPositionsCheck = 0;
datetime lastOrdersCheck = 0;
datetime lastMessageSent = 0;
string lastPositionsHash = "";
string lastOrdersHash = "";

// Forward declarations
string GetAccountInfo();
string GetOpenPositions();
string GetPendingOrders();
void ProcessSocketError(string functionName, int errorCode);
void SendData(string data);
bool HasPositionsChanged();
bool HasOrdersChanged();
bool CanSendMessage();
string CalculatePositionsHash();
string CalculateOrdersHash();

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
   expertStatus = STATUS_CONNECTING;
   ConnectSocket();
   
   // Initialize tracking variables
   lastEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastPositionsTotal = PositionsTotal();
   lastOrdersTotal = OrdersTotal();
   lastPositionsCheck = TimeCurrent();
   lastOrdersCheck = TimeCurrent();
   lastMessageSent = TimeCurrent();
   
   // Send initial account data
   if(IsSocketConnected()) {
      SendData(GetAccountInfo());
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   CloseClean();
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Handle reconnection if needed
   if(expertStatus == STATUS_DISCONNECTED || expertStatus == STATUS_ERROR) {
      if(int(TimeCurrent() - lastConnectionAttempt) >= reconnectDelay) {
         Print("Attempting to reconnect...");
         expertStatus = STATUS_RECONNECTING;
         ConnectSocket();
      }
      return;
   }
   
   if(!IsSocketConnected()) return;
   
   // Check for equity changes
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(MathAbs(currentEquity - lastEquity) > 0.01) {
      SendData(GetUpdateInfo());
      lastEquity = currentEquity;
   }
   
   // Check for position changes
   if(HasPositionsChanged()) {
      SendData(GetOpenPositions());
      lastPositionsTotal = PositionsTotal();
      lastPositionsCheck = TimeCurrent();
      lastPositionsHash = CalculatePositionsHash();
   }
   
   // Check for pending orders changes
   if(HasOrdersChanged()) {
      SendData(GetPendingOrders());
      lastOrdersTotal = OrdersTotal();
      lastOrdersCheck = TimeCurrent();
      lastOrdersHash = CalculateOrdersHash();
   }
}
//+------------------------------------------------------------------+
//| Socket connection function                                         |
//+------------------------------------------------------------------+
void ConnectSocket() {
   if(client == INVALID_SOCKET64) {
      lastConnectionAttempt = TimeCurrent();
      
      char wsaData[]; ArrayResize(wsaData,sizeof(WSAData));
      int res = WSAStartup(MAKEWORD(2,2),wsaData);
      if(res != 0) {
         ProcessSocketError(__FUNCTION__, res);
         return;
      }

      client = socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
      if(client == INVALID_SOCKET64) {
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
      if(res == SOCKET_ERROR) {
         int err = WSAGetLastError();
         if(err != WSAEISCONN) {
            ProcessSocketError(__FUNCTION__, err);
            return;
         }
      }

      int non_block=1;
      res = ioctlsocket(client,(int)FIONBIO,non_block);
      if(res != NO_ERROR) {
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
void CloseClean() {
   if(client != INVALID_SOCKET64) {
      closesocket(client);
      client = INVALID_SOCKET64;
   }
   WSACleanup();
   expertStatus = STATUS_DISCONNECTED;
   Print(__FUNCTION__," > socket closed...");
}

//+------------------------------------------------------------------+
//| Account information function                                       |
//+------------------------------------------------------------------+
string GetAccountInfo() {
   CJAVal data;
   data["type"] = "account";
   data["login"] = AccountInfoInteger(ACCOUNT_LOGIN);
   data["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   data["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
   data["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
   data["freeMargin"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   data["profit"] = AccountInfoDouble(ACCOUNT_PROFIT);
   data["currency"] = AccountInfoString(ACCOUNT_CURRENCY);
   data["leverage"] = AccountInfoInteger(ACCOUNT_LEVERAGE);
   data["name"] = AccountInfoString(ACCOUNT_NAME);
   data["server"] = AccountInfoString(ACCOUNT_SERVER);
   data["company"] = AccountInfoString(ACCOUNT_COMPANY);
   
   return data.Serialize();
}

string GetUpdateInfo() {
   CJAVal data;
   data["type"] = "update";
   data["login"] = AccountInfoInteger(ACCOUNT_LOGIN);
   data["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   data["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
   data["positions"];
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      CJAVal position;
      position["symbol"] = PositionGetString(POSITION_SYMBOL);
      position["type"] = PositionGetInteger(POSITION_TYPE);
      position["volume"] = PositionGetDouble(POSITION_VOLUME);
      position["openPrice"] = PositionGetDouble(POSITION_PRICE_OPEN);
      position["currentPrice"] = PositionGetDouble(POSITION_PRICE_CURRENT);
      position["sl"] = PositionGetDouble(POSITION_SL);
      position["tp"] = PositionGetDouble(POSITION_TP);
      position["profit"] = PositionGetDouble(POSITION_PROFIT);
      position["swap"] = PositionGetDouble(POSITION_SWAP);
      
      data["positions"].Add(position);
   }
   return data.Serialize();
}

//+------------------------------------------------------------------+
//| Open positions function                                            |
//+------------------------------------------------------------------+
string GetOpenPositions() {
   CJAVal data;
   data["type"] = "positions";
   data["positions"];
   
   for(int i = 0; i < PositionsTotal(); i++) {
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
      
      data["positions"].Add(position);
   }
   
   return data.Serialize();
}

//+------------------------------------------------------------------+
//| Pending orders function                                            |
//+------------------------------------------------------------------+
string GetPendingOrders() {
   CJAVal data;
   data["type"] = "orders";
   data["orders"];
   
   for(int i = 0; i < OrdersTotal(); i++) {
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
      
      data["orders"].Add(order);
   }
   
   return data.Serialize();
}

//+------------------------------------------------------------------+
//| Send data function                                                 |
//+------------------------------------------------------------------+
void SendData(string data) {
   if(!IsSocketConnected()) return;
   
   // Add message terminator
   data = data + "\n";
   
   uchar dataArray[];
   StringToCharArray(data, dataArray);
   if(send(client, dataArray, ArraySize(dataArray)-1, 0) == SOCKET_ERROR) {
      ProcessSocketError(__FUNCTION__, WSAGetLastError());
   }
}

//+------------------------------------------------------------------+
//| Check if positions have changed                                    |
//+------------------------------------------------------------------+
bool HasPositionsChanged() {
   // First check total number of positions
   if(PositionsTotal() != lastPositionsTotal) return true;
   
   // If total is same, check for changes in existing positions
   string currentHash = CalculatePositionsHash();
   return currentHash != lastPositionsHash;
}

//+------------------------------------------------------------------+
//| Check if orders have changed                                       |
//+------------------------------------------------------------------+
bool HasOrdersChanged() {
   // First check total number of orders
   if(OrdersTotal() != lastOrdersTotal) return true;
   
   // If total is same, check for changes in existing orders
   string currentHash = CalculateOrdersHash();
   return currentHash != lastOrdersHash;
}

//+------------------------------------------------------------------+
//| Calculate hash for positions                                       |
//+------------------------------------------------------------------+
string CalculatePositionsHash() {
   string hash = "";
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Combine key position properties into a string
      hash += StringFormat("%d|%s|%.5f|%.5f|",
         ticket,
         PositionGetDouble(POSITION_VOLUME),
         PositionGetDouble(POSITION_SL),
         PositionGetDouble(POSITION_TP)
      );
   }
   
   return hash;
}

//+------------------------------------------------------------------+
//| Calculate hash for orders                                          |
//+------------------------------------------------------------------+
string CalculateOrdersHash() {
   string hash = "";
   
   for(int i = 0; i < OrdersTotal(); i++) {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      
      // Combine key order properties into a string
      hash += StringFormat("%d|%s|%d|%.5f|%.5f|%.5f|%.5f|",
         ticket,
         OrderGetString(ORDER_SYMBOL),
         OrderGetInteger(ORDER_TYPE),
         OrderGetDouble(ORDER_VOLUME_INITIAL),
         OrderGetDouble(ORDER_PRICE_OPEN),
         OrderGetDouble(ORDER_SL),
         OrderGetDouble(ORDER_TP)
      );
   }
   
   return hash;
}

//+------------------------------------------------------------------+
//| Error handling function                                            |
//+------------------------------------------------------------------+
void ProcessSocketError(string functionName, int errorCode) {
   expertStatus = STATUS_ERROR;
   Print(functionName, " > Error: ", WSAErrorDescript(errorCode));
   CloseClean();
}

//+------------------------------------------------------------------+
//| Socket connection check function                                   |
//+------------------------------------------------------------------+
bool IsSocketConnected() {
   return client != INVALID_SOCKET64;
} 