//+------------------------------------------------------------------+
//|                                                HeikinAshi_EA.mq5 |
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
input int                MagicNumber = 321098;   // Magic Number

//--- global variables
CTrade  trade;
int     ha_handle;
double  ha_open_buffer[2];
double  ha_close_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Heikin Ashi handle
   ha_handle = iHeikinAshi(_Symbol, _Period);

   if(ha_handle == INVALID_HANDLE)
     {
      printf("Error creating Heikin Ashi indicator");
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
   IndicatorRelease(ha_handle);
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

//--- get Heikin Ashi values for the last 2 completed bars
   if(CopyBuffer(ha_handle, 0, 1, 2, ha_open_buffer) != 2 ||  // HA Open
      CopyBuffer(ha_handle, 3, 1, 2, ha_close_buffer) != 2)   // HA Close
     {
      printf("Error copying Heikin Ashi buffers");
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
// A Heikin Ashi candle is bullish if ha_close > ha_open
// A Heikin Ashi candle is bearish if ha_close < ha_open

//--- check for buy signal (Trend flips from bearish to bullish)
   if(ha_close_buffer[1] < ha_open_buffer[1] && ha_close_buffer[0] > ha_open_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Heikin Ashi Buy Signal");
        }
     }

//--- check for sell signal (Trend flips from bullish to bearish)
   if(ha_close_buffer[1] > ha_open_buffer[1] && ha_close_buffer[0] < ha_open_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Heikin Ashi Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
