//+------------------------------------------------------------------+
//|                                                       RVI_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                RVIPeriod = 10;         // RVI Period
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 909090;   // Magic Number

//--- global variables
CTrade  trade;
int     rvi_handle;
double  rvi_main_buffer[2];
double  rvi_signal_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get RVI handle
   rvi_handle = iRVI(_Symbol, _Period, RVIPeriod);

   if(rvi_handle == INVALID_HANDLE)
     {
      printf("Error creating RVI indicator");
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
   IndicatorRelease(rvi_handle);
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

//--- get RVI values for the last 2 completed bars
   if(CopyBuffer(rvi_handle, 0, 1, 2, rvi_main_buffer) != 2 ||    // Main Line
      CopyBuffer(rvi_handle, 1, 1, 2, rvi_signal_buffer) != 2)    // Signal Line
     {
      printf("Error copying RVI buffers");
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

//--- check for buy signal (RVI main line crosses above signal line)
   if(rvi_main_buffer[1] <= rvi_signal_buffer[1] && rvi_main_buffer[0] > rvi_signal_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "RVI Buy Signal");
        }
     }

//--- check for sell signal (RVI main line crosses below signal line)
   if(rvi_main_buffer[1] >= rvi_signal_buffer[1] && rvi_main_buffer[0] < rvi_signal_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "RVI Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
