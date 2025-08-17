//+------------------------------------------------------------------+
//|                                                      TRIX_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                TRIXPeriod = 14;          // TRIX Period
input int                SignalPeriod = 9;         // Signal Line MA Period
input ENUM_MA_METHOD     SignalMAMethod = MODE_SMA;// Signal Line MA Method
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE; // Applied Price
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 223344;   // Magic Number

//--- global variables
CTrade  trade;
int     trix_handle;
int     signal_handle;
double  trix_buffer[2];
double  signal_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get TRIX handle
   trix_handle = iTRIX(_Symbol, _Period, TRIXPeriod, AppliedPrice);
   if(trix_handle == INVALID_HANDLE)
     {
      printf("Error creating TRIX indicator");
      return(INIT_FAILED);
     }

//--- get Signal Line handle (MA on TRIX data)
   signal_handle = iMA(_Symbol, _Period, SignalPeriod, 0, SignalMAMethod, trix_handle);
   if(signal_handle == INVALID_HANDLE)
     {
      printf("Error creating Signal Line indicator on TRIX");
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
   IndicatorRelease(trix_handle);
   IndicatorRelease(signal_handle);
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
   if(CopyBuffer(trix_handle, 0, 1, 2, trix_buffer) != 2 ||
      CopyBuffer(signal_handle, 0, 1, 2, signal_buffer) != 2)
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

//--- check for buy signal (TRIX crosses above its signal line)
   if(trix_buffer[1] <= signal_buffer[1] && trix_buffer[0] > signal_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "TRIX Buy Signal");
        }
     }

//--- check for sell signal (TRIX crosses below its signal line)
   if(trix_buffer[1] >= signal_buffer[1] && trix_buffer[0] < signal_buffer[0])
     {
      if(!is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "TRIX Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
