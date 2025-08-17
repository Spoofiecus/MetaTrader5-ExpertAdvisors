//+------------------------------------------------------------------+
//|                                       AwesomeOscillator_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 654321;   // Magic Number

//--- global variables
CTrade  trade;
int     ao_handle;
double  ao_buffer[3];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Awesome Oscillator handle
   ao_handle = iAO(_Symbol, _Period);

   if(ao_handle == INVALID_HANDLE)
     {
      printf("Error creating Awesome Oscillator indicator");
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
   IndicatorRelease(ao_handle);
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

//--- get AO values for the last 3 completed bars
   if(CopyBuffer(ao_handle, 0, 1, 3, ao_buffer) != 3)
     {
      printf("Error copying Awesome Oscillator buffer");
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
// ao_buffer[2] = bar n-2 (oldest)
// ao_buffer[1] = bar n-1 (middle)
// ao_buffer[0] = bar n   (most recent completed)

//--- check for Bullish Saucer pattern
   bool bullish_saucer = (ao_buffer[2] > 0 && ao_buffer[1] > 0 && ao_buffer[0] > 0) && // All above zero
                         (ao_buffer[2] > ao_buffer[1]) && // First bar is higher than second (dip)
                         (ao_buffer[0] > ao_buffer[1]);   // Third bar is higher than second (recovery)

   if(bullish_saucer)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "AO Bullish Saucer");
        }
     }

//--- check for Bearish Saucer pattern
   bool bearish_saucer = (ao_buffer[2] < 0 && ao_buffer[1] < 0 && ao_buffer[0] < 0) && // All below zero
                         (ao_buffer[2] < ao_buffer[1]) && // First bar is lower than second (bump)
                         (ao_buffer[0] < ao_buffer[1]);   // Third bar is lower than second (fall)

   if(bearish_saucer)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "AO Bearish Saucer");
        }
     }
  }
//+------------------------------------------------------------------+
