//+------------------------------------------------------------------+
//|                                        OBV_MA_Crossover_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input ENUM_APPLIED_VOLUME OBVAppliedVolume = VOLUME_TICK; // OBV Applied Volume
input int                 MAPeriod = 20;          // MA Period for OBV
input ENUM_MA_METHOD      MAMethod = MODE_SMA;    // MA Method for OBV
input double              LotSize = 0.01;         // Lot Size
input int                 StopLossPips = 50;      // Stop Loss in Pips
input int                 TakeProfitPips = 100;   // Take Profit in Pips
input int                 MagicNumber = 404040;   // Magic Number

//--- global variables
CTrade  trade;
int     obv_handle;
int     ma_on_obv_handle;
double  obv_buffer[2];
double  ma_on_obv_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get OBV handle
   obv_handle = iOBV(_Symbol, _Period, OBVAppliedVolume);
   if(obv_handle == INVALID_HANDLE)
     {
      printf("Error creating OBV indicator");
      return(INIT_FAILED);
     }

//--- get MA on OBV handle
   ma_on_obv_handle = iMA(_Symbol, _Period, MAPeriod, 0, MAMethod, obv_handle);
   if(ma_on_obv_handle == INVALID_HANDLE)
     {
      printf("Error creating MA on OBV indicator");
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
//--- release indicator handles
   IndicatorRelease(obv_handle);
   IndicatorRelease(ma_on_obv_handle);
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

//--- get indicator values for the last 2 completed bars
   if(CopyBuffer(obv_handle, 0, 1, 2, obv_buffer) != 2 ||
      CopyBuffer(ma_on_obv_handle, 0, 1, 2, ma_on_obv_buffer) != 2)
     {
      printf("Error copying indicator buffers");
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

//--- check for buy signal (OBV crosses above its MA)
   if(obv_buffer[1] <= ma_on_obv_buffer[1] && obv_buffer[0] > ma_on_obv_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "OBV MA Buy Signal");
        }
     }

//--- check for sell signal (OBV crosses below its MA)
   if(obv_buffer[1] >= ma_on_obv_buffer[1] && obv_buffer[0] < ma_on_obv_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "OBV MA Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
