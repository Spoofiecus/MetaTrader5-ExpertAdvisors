//+------------------------------------------------------------------+
//|                                         EngulfingPattern_EA.mq5 |
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
input int                MagicNumber = 432109;   // Magic Number

//--- global variables
CTrade  trade;
double  open_buffer[2];
double  high_buffer[2];
double  low_buffer[2];
double  close_buffer[2];

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

//--- get OHLC values for the last 2 completed bars
   if(CopyOpen(_Symbol, _Period, 1, 2, open_buffer) != 2 ||
      CopyHigh(_Symbol, _Period, 1, 2, high_buffer) != 2 ||
      CopyLow(_Symbol, _Period, 1, 2, low_buffer) != 2 ||
      CopyClose(_Symbol, _Period, 1, 2, close_buffer) != 2)
     {
      printf("Error copying price data");
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
// buffer[1] = value on the bar before the most recently completed bar (the engulfed candle)
// buffer[0] = value on the most recently completed bar (the engulfing candle)

//--- check for Bullish Engulfing pattern
   bool bullish_engulfing = (close_buffer[1] < open_buffer[1]) && // Previous bar is bearish
                            (close_buffer[0] > open_buffer[0]) && // Current bar is bullish
                            (close_buffer[0] > open_buffer[1]) && // Current close is above previous open
                            (open_buffer[0] < close_buffer[1]);   // Current open is below previous close

   if(bullish_engulfing)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Bullish Engulfing");
        }
     }

//--- check for Bearish Engulfing pattern
   bool bearish_engulfing = (close_buffer[1] > open_buffer[1]) && // Previous bar is bullish
                            (close_buffer[0] < open_buffer[0]) && // Current bar is bearish
                            (close_buffer[0] < open_buffer[1]) && // Current close is below previous open
                            (open_buffer[0] > close_buffer[1]);   // Current open is above previous close

   if(bearish_engulfing)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Bearish Engulfing");
        }
     }
  }
//+------------------------------------------------------------------+
