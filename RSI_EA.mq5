//+------------------------------------------------------------------+
//|                                                       RSI_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                RSIPeriod = 14;         // RSI Period
input int                OverboughtLevel = 70;   // RSI Overbought Level
input int                OversoldLevel = 30;     // RSI Oversold Level
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 54321;    // Magic Number

//--- global variables
CTrade trade;
int    rsi_handle;
double rsi_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get RSI handle
   rsi_handle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);

   if(rsi_handle == INVALID_HANDLE)
     {
      printf("Error creating RSI indicator");
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
   IndicatorRelease(rsi_handle);
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

//--- get RSI values for the last 2 completed bars
   if(CopyBuffer(rsi_handle, 0, 1, 2, rsi_buffer) != 2)
     {
      printf("Error copying RSI buffer");
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
// rsi_buffer[1] = RSI value on the bar before the most recently completed bar
// rsi_buffer[0] = RSI value on the most recently completed bar

//--- check for buy signal (RSI crosses above oversold level)
   if(rsi_buffer[1] <= OversoldLevel && rsi_buffer[0] > OversoldLevel)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "RSI Buy Signal");
        }
     }

//--- check for sell signal (RSI crosses below overbought level)
   if(rsi_buffer[1] >= OverboughtLevel && rsi_buffer[0] < OverboughtLevel)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "RSI Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
