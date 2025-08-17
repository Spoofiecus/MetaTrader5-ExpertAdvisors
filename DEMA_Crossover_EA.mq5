//+------------------------------------------------------------------+
//|                                            DEMA_Crossover_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                FastDEMAPeriod = 12;      // Fast DEMA Period
input int                SlowDEMAPeriod = 26;      // Slow DEMA Period
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE; // Applied Price
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 445566;   // Magic Number

//--- global variables
CTrade  trade;
int     fast_dema_handle;
int     slow_dema_handle;
double  fast_dema_buffer[2];
double  slow_dema_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get DEMA handles
   fast_dema_handle = iDEMA(_Symbol, _Period, FastDEMAPeriod, 0, AppliedPrice);
   slow_dema_handle = iDEMA(_Symbol, _Period, SlowDEMAPeriod, 0, AppliedPrice);

   if(fast_dema_handle == INVALID_HANDLE || slow_dema_handle == INVALID_HANDLE)
     {
      printf("Error creating DEMA indicators");
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
//--- release indicator handles
   IndicatorRelease(fast_dema_handle);
   IndicatorRelease(slow_dema_handle);
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

//--- get DEMA values for the last 2 completed bars
   if(CopyBuffer(fast_dema_handle, 0, 1, 2, fast_dema_buffer) != 2 ||
      CopyBuffer(slow_dema_handle, 0, 1, 2, slow_dema_buffer) != 2)
     {
      printf("Error copying DEMA buffers");
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

//--- check for buy signal (Fast DEMA crosses above Slow DEMA)
   if(fast_dema_buffer[1] <= slow_dema_buffer[1] && fast_dema_buffer[0] > slow_dema_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "DEMA Crossover Buy");
        }
     }

//--- check for sell signal (Fast DEMA crosses below Slow DEMA)
   if(fast_dema_buffer[1] >= slow_dema_buffer[1] && fast_dema_buffer[0] < slow_dema_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "DEMA Crossover Sell");
        }
     }
  }
//+------------------------------------------------------------------+
