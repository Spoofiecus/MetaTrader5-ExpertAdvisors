//+------------------------------------------------------------------+
//|                                                Stochastic_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                KPeriod = 5;            // Stochastic %K Period
input int                DPeriod = 3;            // Stochastic %D Period
input int                Slowing = 3;            // Stochastic Slowing
input ENUM_MA_METHOD     MAMethod = MODE_SMA;    // Stochastic MA Method
input int                OverboughtLevel = 80;   // Stochastic Overbought Level
input int                OversoldLevel = 20;     // Stochastic Oversold Level
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 65432;    // Magic Number

//--- global variables
CTrade  trade;
int     stochastic_handle;
double  main_buffer[2]; // For the main line
double  signal_buffer[2]; // For the signal line (not used in this strategy, but good for reference)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Stochastic handle
   stochastic_handle = iStochastic(_Symbol, _Period, KPeriod, DPeriod, Slowing, MAMethod, STO_LOWHIGH);

   if(stochastic_handle == INVALID_HANDLE)
     {
      printf("Error creating Stochastic indicator");
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
   IndicatorRelease(stochastic_handle);
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

//--- get Stochastic values for the last 2 completed bars (Main Line)
   if(CopyBuffer(stochastic_handle, 0, 1, 2, main_buffer) != 2) // Buffer 0 is the Main Line
     {
      printf("Error copying Stochastic main buffer");
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
// main_buffer[1] = Stochastic value on the bar before the most recently completed bar
// main_buffer[0] = Stochastic value on the most recently completed bar

//--- check for buy signal (Stochastic crosses above oversold level)
   if(main_buffer[1] <= OversoldLevel && main_buffer[0] > OversoldLevel)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Stochastic Buy Signal");
        }
     }

//--- check for sell signal (Stochastic crosses below overbought level)
   if(main_buffer[1] >= OverboughtLevel && main_buffer[0] < OverboughtLevel)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Stochastic Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
