//+------------------------------------------------------------------+
//|                                                       ADX_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                ADXPeriod = 14;         // ADX Period
input int                ADXThreshold = 25;      // ADX Trend Strength Threshold
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 210938;   // Magic Number

//--- global variables
CTrade  trade;
int     adx_handle;
double  adx_main_buffer[2];
double  plus_di_buffer[2];
double  minus_di_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get ADX handle
   adx_handle = iADX(_Symbol, _Period, ADXPeriod);

   if(adx_handle == INVALID_HANDLE)
     {
      printf("Error creating ADX indicator");
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
   IndicatorRelease(adx_handle);
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

//--- get ADX values for the last 2 completed bars
   if(CopyBuffer(adx_handle, 0, 1, 2, adx_main_buffer) != 2 || // Main ADX Line
      CopyBuffer(adx_handle, 1, 1, 2, plus_di_buffer) != 2 ||  // +DI Line
      CopyBuffer(adx_handle, 2, 1, 2, minus_di_buffer) != 2)   // -DI Line
     {
      printf("Error copying ADX buffers");
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

//--- check for buy signal (+DI crosses above -DI and ADX is strong)
   if(plus_di_buffer[1] <= minus_di_buffer[1] && plus_di_buffer[0] > minus_di_buffer[0] && adx_main_buffer[0] > ADXThreshold)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "ADX Buy Signal");
        }
     }

//--- check for sell signal (-DI crosses above +DI and ADX is strong)
   if(minus_di_buffer[1] <= plus_di_buffer[1] && minus_di_buffer[0] > plus_di_buffer[0] && adx_main_buffer[0] > ADXThreshold)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "ADX Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
