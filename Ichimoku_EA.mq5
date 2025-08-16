//+------------------------------------------------------------------+
//|                                                  Ichimoku_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                TenkanSen = 9;          // Tenkan-sen Period
input int                KijunSen = 26;          // Kijun-sen Period
input int                SenkouSpanB = 52;       // Senkou Span B Period
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 102938;   // Magic Number

//--- global variables
CTrade  trade;
int     ichimoku_handle;
double  senkou_a_buffer[2];
double  senkou_b_buffer[2];
double  close_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Ichimoku handle
   ichimoku_handle = iIchimoku(_Symbol, _Period, TenkanSen, KijunSen, SenkouSpanB);

   if(ichimoku_handle == INVALID_HANDLE)
     {
      printf("Error creating Ichimoku indicator");
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
   IndicatorRelease(ichimoku_handle);
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

//--- get Ichimoku and price values for the last 2 completed bars
   if(CopyBuffer(ichimoku_handle, 2, 1, 2, senkou_a_buffer) != 2 || // Senkou Span A
      CopyBuffer(ichimoku_handle, 3, 1, 2, senkou_b_buffer) != 2 || // Senkou Span B
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

//--- Define cloud boundaries
   double cloud_top_curr = fmax(senkou_a_buffer[0], senkou_b_buffer[0]);
   double cloud_bottom_curr = fmin(senkou_a_buffer[0], senkou_b_buffer[0]);
   double cloud_top_prev = fmax(senkou_a_buffer[1], senkou_b_buffer[1]);
   double cloud_bottom_prev = fmin(senkou_a_buffer[1], senkou_b_buffer[1]);

//--- check for buy signal (Price closes above the cloud)
   if(close_buffer[1] <= cloud_top_prev && close_buffer[0] > cloud_top_curr)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Ichimoku Buy Signal");
        }
     }

//--- check for sell signal (Price closes below the cloud)
   if(close_buffer[1] >= cloud_bottom_prev && close_buffer[0] < cloud_bottom_curr)
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Ichimoku Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
