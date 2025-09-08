//+------------------------------------------------------------------+
//|                                        MACrossoverScalpingEA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                FastMAPeriod = 5;       // Fast Moving Average Period
input int                SlowMAPeriod = 20;      // Slow Moving Average Period
input ENUM_MA_METHOD     MAMethod = MODE_EMA;    // Moving Average Method
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 10;      // Stop Loss in Pips
input int                TakeProfitPips = 10;    // Take Profit in Pips
input int                MagicNumber = 12345;    // Magic Number

//--- global variables
CTrade trade;
int    fast_ma_handle;
int    slow_ma_handle;
double fast_ma_buffer[2];
double slow_ma_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get moving average handles
   fast_ma_handle = iMA(_Symbol, _Period, FastMAPeriod, 0, MAMethod, PRICE_CLOSE);
   slow_ma_handle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MAMethod, PRICE_CLOSE);

   if(fast_ma_handle == INVALID_HANDLE || slow_ma_handle == INVALID_HANDLE)
     {
      printf("Error creating indicators");
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
   IndicatorRelease(fast_ma_handle);
   IndicatorRelease(slow_ma_handle);
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

//--- get moving average values for the last 2 completed bars
   if(CopyBuffer(fast_ma_handle, 0, 1, 2, fast_ma_buffer) != 2 ||
      CopyBuffer(slow_ma_handle, 0, 1, 2, slow_ma_buffer) != 2)
     {
      printf("Error copying indicator buffers");
      return;
     }

//--- check for existing position for this symbol and magic number
   long position_type = 0; // 0 = no position, 1 = buy, -1 = sell

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            position_type = 1;
           }
         else
           {
            position_type = -1;
           }
         break;
        }
     }

//--- Crossover logic
// buffer[1] = value on the bar before the most recently completed bar
// buffer[0] = value on the most recently completed bar

//--- check for buy signal (golden cross)
   if(fast_ma_buffer[1] <= slow_ma_buffer[1] && fast_ma_buffer[0] > slow_ma_buffer[0])
     {
      // If a sell position is open, close it (reversal)
      if(position_type == -1)
        {
         trade.PositionClose(_Symbol);
         position_type = 0;
        }
      // If no position is open, open a buy
      if(position_type == 0)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Golden Cross");
        }
     }

//--- check for sell signal (death cross)
   if(fast_ma_buffer[1] >= slow_ma_buffer[1] && fast_ma_buffer[0] < slow_ma_buffer[0])
     {
      // If a buy position is open, close it (reversal)
      if(position_type == 1)
        {
         trade.PositionClose(_Symbol);
         position_type = 0;
        }
      // If no position is open, open a sell
      if(position_type == 0)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Death Cross");
        }
     }
  }
//+------------------------------------------------------------------+
