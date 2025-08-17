//+------------------------------------------------------------------+
//|                                                 Envelopes_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                MAPeriod = 14;          // MA Period
input ENUM_MA_METHOD     MAMethod = MODE_SMA;    // MA Method
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE; // Applied Price
input double             Deviation = 0.1;        // Deviation in percent
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 808080;   // Magic Number

//--- global variables
CTrade  trade;
int     envelopes_handle;
double  upper_band_buffer[2];
double  lower_band_buffer[2];
double  close_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Envelopes handle
   envelopes_handle = iEnvelopes(_Symbol, _Period, MAPeriod, 0, MAMethod, AppliedPrice, Deviation);

   if(envelopes_handle == INVALID_HANDLE)
     {
      printf("Error creating Envelopes indicator");
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
   IndicatorRelease(envelopes_handle);
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
   if(CopyBuffer(envelopes_handle, 0, 1, 2, upper_band_buffer) != 2 || // Upper Band
      CopyBuffer(envelopes_handle, 1, 1, 2, lower_band_buffer) != 2 || // Lower Band
      CopyClose(_Symbol, _Period, 1, 2, close_buffer) != 2)
     {
      printf("Error copying indicator/price buffers");
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

//--- check for buy signal (Price closes above upper band)
   if(close_buffer[1] <= upper_band_buffer[1] && close_buffer[0] > upper_band_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Envelopes Buy Signal");
        }
     }

//--- check for sell signal (Price closes below lower band)
   if(close_buffer[1] >= lower_band_buffer[1] && close_buffer[0] < lower_band_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Envelopes Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
