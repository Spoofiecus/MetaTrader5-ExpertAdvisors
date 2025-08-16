//+------------------------------------------------------------------+
//|                                             ParabolicSAR_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input double             SAR_Step = 0.02;        // SAR Step
input double             SAR_Maximum = 0.2;      // SAR Maximum
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips (for protection)
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 98765;    // Magic Number

//--- global variables
CTrade  trade;
int     sar_handle;
double  sar_buffer[2];
double  high_buffer[2];
double  low_buffer[2];

//+------------------------------------------------------------------+
//| Helper function to close positions by type                       |
//+------------------------------------------------------------------+
void ClosePositions(int type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         if(PositionGetInteger(POSITION_TYPE) == type)
           {
            trade.PositionClose(PositionGetTicket(i));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper function to count open positions by type                  |
//+------------------------------------------------------------------+
int GetOpenPositions(int type)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         if(PositionGetInteger(POSITION_TYPE) == type)
           {
            count++;
           }
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Parabolic SAR handle
   sar_handle = iSAR(_Symbol, _Period, SAR_Step, SAR_Maximum);

   if(sar_handle == INVALID_HANDLE)
     {
      printf("Error creating Parabolic SAR indicator");
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
   IndicatorRelease(sar_handle);
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

//--- get SAR and price values for the last 2 completed bars
   if(CopyBuffer(sar_handle, 0, 1, 2, sar_buffer) != 2 ||
      CopyHigh(_Symbol, _Period, 1, 2, high_buffer) != 2 ||
      CopyLow(_Symbol, _Period, 1, 2, low_buffer) != 2)
     {
      printf("Error copying indicator/price buffers");
      return;
     }

//--- Trading logic
// buffer[1] = value on the bar before the most recently completed bar
// buffer[0] = value on the most recently completed bar

//--- check for buy signal (SAR flips below price)
   bool buy_signal = sar_buffer[1] > high_buffer[1] && sar_buffer[0] < low_buffer[0];

//--- check for sell signal (SAR flips above price)
   bool sell_signal = sar_buffer[1] < low_buffer[1] && sar_buffer[0] > high_buffer[0];

//--- Execute buy signal
   if(buy_signal)
     {
      ClosePositions(OP_SELL); // Close any open sell positions
      if(GetOpenPositions(OP_BUY) == 0) // If no buy position is open
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Parabolic SAR Buy");
        }
     }

//--- Execute sell signal
   if(sell_signal)
     {
      ClosePositions(OP_BUY); // Close any open buy positions
      if(GetOpenPositions(OP_SELL) == 0) // If no sell position is open
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Parabolic SAR Sell");
        }
     }
  }
//+------------------------------------------------------------------+
