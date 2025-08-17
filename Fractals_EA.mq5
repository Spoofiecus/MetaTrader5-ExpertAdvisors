//+------------------------------------------------------------------+
//|                                                    Fractals_EA.mq5 |
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
input int                MagicNumber = 876543;   // Magic Number

//--- global variables
CTrade  trade;
int     fractals_handle;
double  up_fractal_buffer[4];
double  down_fractal_buffer[4];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Fractals handle
   fractals_handle = iFractals(_Symbol, _Period);

   if(fractals_handle == INVALID_HANDLE)
     {
      printf("Error creating Fractals indicator");
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
   IndicatorRelease(fractals_handle);
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

//--- get Fractal values for the last 4 completed bars
// A fractal at bar [i] is confirmed at the close of bar [i-2]
// So, a fractal at bar [2] is the most recent one we can trade
   if(CopyBuffer(fractals_handle, 0, 1, 4, up_fractal_buffer) != 4 ||    // Upper Fractals
      CopyBuffer(fractals_handle, 1, 1, 4, down_fractal_buffer) != 4)    // Lower Fractals
     {
      printf("Error copying Fractals buffers");
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
// We check for a fractal confirmed on the bar at index [2]
// To avoid re-trading the same fractal, we check that a fractal did NOT exist on bar [3]

//--- check for new Up Fractal
   bool new_up_fractal = up_fractal_buffer[3] == EMPTY_VALUE && up_fractal_buffer[2] != EMPTY_VALUE;

   if(new_up_fractal)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Fractal Buy Signal");
        }
     }

//--- check for new Down Fractal
   bool new_down_fractal = down_fractal_buffer[3] == EMPTY_VALUE && down_fractal_buffer[2] != EMPTY_VALUE;

   if(new_down_fractal)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Fractal Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
