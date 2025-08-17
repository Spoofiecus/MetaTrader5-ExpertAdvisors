//+------------------------------------------------------------------+
//|                                                       CCI_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                CCIPeriod = 14;         // CCI Period
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_TYPICAL; // Applied Price
input int                OverboughtLevel = 100;  // Overbought Level
input int                OversoldLevel = -100;   // Oversold Level
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 101010;   // Magic Number

//--- global variables
CTrade  trade;
int     cci_handle;
double  cci_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get CCI handle
   cci_handle = iCCI(_Symbol, _Period, CCIPeriod, AppliedPrice);

   if(cci_handle == INVALID_HANDLE)
     {
      printf("Error creating CCI indicator");
      return(INIT_FAILED);
     }

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- release indicator handle
   IndicatorRelease(cci_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- static variable to store the bar time. This ensures the logic runs only once per bar.
   static datetime last_bar_time = 0;
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   if(current_bar_time == last_bar_time)
     {
      return; // Not a new bar, do nothing
     }
   last_bar_time = current_bar_time;

//--- get CCI values for the last 2 completed bars
   if(CopyBuffer(cci_handle, 0, 1, 2, cci_buffer) != 2)
     {
      printf("Error copying CCI buffer");
      return;
     }

//--- check if a trade is already open for this symbol and magic number
   bool is_trade_open = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         is_trade_open = true;
         break;
        }
     }

//--- Trading logic
// buffer[1] = value on the bar before the most recently completed bar
// buffer[0] = value on the most recently completed bar

//--- check for buy signal (CCI returns from oversold)
   if(cci_buffer[1] <= OversoldLevel && cci_buffer[0] > OversoldLevel)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "CCI Buy Signal");
        }
     }

//--- check for sell signal (CCI returns from overbought)
   if(cci_buffer[1] >= OverboughtLevel && cci_buffer[0] < OverboughtLevel)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "CCI Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
