//+------------------------------------------------------------------+
//|                                                    PinBar_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input double             WickBodyRatioMin = 2.0;   // Minimum ratio of long wick to body
input double             OtherWickBodyRatioMax = 1.0; // Maximum ratio of short wick to body
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 667788;   // Magic Number

//--- global variables
CTrade  trade;
MqlRates rates[2]; // To store OHLC data for the last 2 bars

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
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

//--- get OHLC values for the last completed bar
   if(CopyRates(_Symbol, _Period, 1, 1, rates) != 1)
     {
      printf("Error copying rates data");
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

//--- Trading logic for the last completed bar (rates[0])
   double bar_open = rates[0].open;
   double bar_high = rates[0].high;
   double bar_low = rates[0].low;
   double bar_close = rates[0].close;

   double body_size = fabs(bar_open - bar_close);
   double upper_wick = bar_high - fmax(bar_open, bar_close);
   double lower_wick = fmin(bar_open, bar_close) - bar_low;

   if(body_size > 0) // Avoid dojis
     {
      //--- check for Bullish Pin Bar (Hammer)
      bool bullish_pin_bar = (lower_wick > body_size * WickBodyRatioMin) && (upper_wick < body_size * OtherWickBodyRatioMax);

      if(bullish_pin_bar && !is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Bullish Pin Bar");
        }

      //--- check for Bearish Pin Bar (Shooting Star)
      bool bearish_pin_bar = (upper_wick > body_size * WickBodyRatioMin) && (lower_wick < body_size * OtherWickBodyRatioMax);

      if(bearish_pin_bar && !is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Bearish Pin Bar");
        }
     }
  }
//+------------------------------------------------------------------+
