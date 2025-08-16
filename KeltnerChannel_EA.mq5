//+------------------------------------------------------------------+
//|                                           KeltnerChannel_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                MAPeriod = 20;          // Moving Average Period
input ENUM_MA_METHOD     MAMethod = MODE_EMA;    // Moving Average Method
input int                ATRPeriod = 10;         // ATR Period
input double             ATRMultiplier = 2.0;    // ATR Multiplier
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 543210;   // Magic Number

//--- global variables
CTrade  trade;
int     ma_handle;
int     atr_handle;
double  ma_buffer[2];
double  atr_buffer[2];
double  close_buffer[2];
double  upper_band[2];
double  lower_band[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get MA handle (for the middle line, using typical price)
   ma_handle = iMA(_Symbol, _Period, MAPeriod, 0, MAMethod, PRICE_TYPICAL);
//--- get ATR handle
   atr_handle = iATR(_Symbol, _Period, ATRPeriod);

   if(ma_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
     {
      printf("Error creating indicators");
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
   IndicatorRelease(ma_handle);
   IndicatorRelease(atr_handle);
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

//--- get indicator and price values for the last 2 completed bars
   if(CopyBuffer(ma_handle, 0, 1, 2, ma_buffer) != 2 ||
      CopyBuffer(atr_handle, 0, 1, 2, atr_buffer) != 2 ||
      CopyClose(_Symbol, _Period, 1, 2, close_buffer) != 2)
     {
      printf("Error copying indicator/price buffers");
      return;
     }

//--- Calculate Keltner Channel bands
   for(int i = 0; i < 2; i++)
     {
      upper_band[i] = ma_buffer[i] + (atr_buffer[i] * ATRMultiplier);
      lower_band[i] = ma_buffer[i] - (atr_buffer[i] * ATRMultiplier);
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

//--- check for buy signal (Price closes above upper band)
   if(close_buffer[1] <= upper_band[1] && close_buffer[0] > upper_band[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Keltner Channel Buy");
        }
     }

//--- check for sell signal (Price closes below lower band)
   if(close_buffer[1] >= lower_band[1] && close_buffer[0] < lower_band[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Keltner Channel Sell");
        }
     }
  }
//+------------------------------------------------------------------+
