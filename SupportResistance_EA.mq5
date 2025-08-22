//+------------------------------------------------------------------+
//|                                       SupportResistance_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Expert Advisor that trades based on support and resistance levels."

#include <Trade/Trade.mqh>

//--- input parameters
input double   LotSize          = 0.01;         // Lot Size
input int      StopLossPips     = 50;           // Stop Loss in Pips
input int      TakeProfitPips   = 100;          // Take Profit in Pips
input int      MagicNumber      = 12345;        // Magic Number
//--- MA Trend Filter
input int      MAPeriod         = 100;          // Moving Average Period
input ENUM_MA_METHOD MAMethod   = MODE_EMA;     // Moving Average Method
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE; // Applied Price

//--- global variables
CTrade  trade;
int     fractals_handle;
int     ma_handle;
double  upper_fractal_buffer[];
double  lower_fractal_buffer[];
double  ma_buffer[];

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

//--- get MA handle
   ma_handle = iMA(_Symbol, _Period, MAPeriod, 0, MAMethod, AppliedPrice);
   if(ma_handle == INVALID_HANDLE)
     {
      printf("Error creating MA indicator");
      return(INIT_FAILED);
     }

//--- Set up arrays for indicator data
   ArraySetAsSeries(upper_fractal_buffer, true);
   ArraySetAsSeries(lower_fractal_buffer, true);
   ArraySetAsSeries(ma_buffer, true);

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- release indicator handles
   IndicatorRelease(fractals_handle);
   IndicatorRelease(ma_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- static variable to store the bar time. This ensures the logic runs only once per bar.
   static datetime last_bar_time = 0;
   MqlRates current_rates[2];
   if(CopyRates(_Symbol, _Period, 0, 2, current_rates) < 2)
     {
      return; // Not enough bars
     }

   datetime current_bar_time = current_rates[1].time;
   if(current_bar_time == last_bar_time)
     {
      return; // Not a new bar, do nothing
     }
   last_bar_time = current_bar_time;

//--- Copy indicator data
   if(CopyBuffer(fractals_handle, 0, 1, 100, upper_fractal_buffer) <= 0 || // Upper fractals
      CopyBuffer(fractals_handle, 1, 1, 100, lower_fractal_buffer) <= 0 || // Lower fractals
      CopyBuffer(ma_handle, 0, 1, 1, ma_buffer) <= 0)                      // MA
     {
      printf("Error copying indicator buffers");
      return;
     }

//--- Find the most recent support and resistance levels
   double resistance = 0;
   double support = 0;

   // Find the first non-empty upper fractal value (resistance), starting from index 2 due to fractal delay
   for(int i = 2; i < 100; i++)
     {
      if(upper_fractal_buffer[i] > 0)
        {
         resistance = upper_fractal_buffer[i];
         break;
        }
     }

   // Find the first non-empty lower fractal value (support), starting from index 2 due to fractal delay
   for(int i = 2; i < 100; i++)
     {
      if(lower_fractal_buffer[i] > 0)
        {
         support = lower_fractal_buffer[i];
         break;
        }
     }

   if(resistance == 0 || support == 0)
     {
      // Not enough data yet
      return;
     }

//--- check if a trade is already open for this symbol and magic number
   bool is_trade_open = false;
   if(PositionsTotal() > 0)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            is_trade_open = true;
            break;
           }
        }
     }

//--- Trading logic
   double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double last_close = current_rates[1].close;
   double ma_value = ma_buffer[0];

//--- check for buy signal (Price breaks above resistance AND is above MA)
   if(last_close > resistance && last_close > ma_value)
     {
      if(!is_trade_open)
        {
         double sl = current_ask - StopLossPips * _Point;
         double tp = current_ask + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, current_ask, sl, tp, "S/R Breakout Buy");
        }
     }

//--- check for sell signal (Price breaks below support AND is below MA)
   if(last_close < support && last_close < ma_value)
     {
      if(!is_trade_open)
        {
         double sl = current_bid + StopLossPips * _Point;
         double tp = current_bid - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, current_bid, sl, tp, "S/R Breakout Sell");
        }
     }
  }
//+------------------------------------------------------------------+
