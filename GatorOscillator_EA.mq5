//+------------------------------------------------------------------+
//|                                           GatorOscillator_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters for Alligator/Gator
input int                JawPeriod = 13;         // Jaw Period
input int                JawShift = 8;           // Jaw Shift
input int                TeethPeriod = 8;        // Teeth Period
input int                TeethShift = 5;         // Teeth Shift
input int                LipsPeriod = 5;         // Lips Period
input int                LipsShift = 3;          // Lips Shift
input ENUM_MA_METHOD     MAMethod = MODE_SMMA;   // MA Method
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_MEDIAN; // Applied Price

//--- input parameters for trading
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                MagicNumber = 765432;   // Magic Number

//--- global variables
CTrade  trade;
int     gator_handle;
int     ao_handle;
double  gator_upper_buffer[3];
double  gator_lower_buffer[3];
double  ao_buffer[1];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Gator Oscillator handle
   gator_handle = iGator(_Symbol, _Period, JawPeriod, JawShift, TeethPeriod, TeethShift, LipsPeriod, LipsShift, MAMethod, AppliedPrice);
//--- get Awesome Oscillator handle for directional filter
   ao_handle = iAO(_Symbol, _Period);

   if(gator_handle == INVALID_HANDLE || ao_handle == INVALID_HANDLE)
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
   IndicatorRelease(gator_handle);
   IndicatorRelease(ao_handle);
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

//--- get indicator values
   if(CopyBuffer(gator_handle, 0, 1, 3, gator_upper_buffer) != 3 || // Gator Upper Histogram
      CopyBuffer(gator_handle, 1, 1, 3, gator_lower_buffer) != 3 || // Gator Lower Histogram
      CopyBuffer(ao_handle, 0, 1, 1, ao_buffer) != 1)               // Awesome Oscillator
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
// buffer[2] = bar n-2 (oldest)
// buffer[1] = bar n-1 (middle)
// buffer[0] = bar n   (most recent completed)

//--- Gator State Logic
   bool was_sleeping = gator_upper_buffer[1] < gator_upper_buffer[2] && fabs(gator_lower_buffer[1]) < fabs(gator_lower_buffer[2]);
   bool is_awakening = gator_upper_buffer[0] > gator_upper_buffer[1] || fabs(gator_lower_buffer[0]) > fabs(gator_lower_buffer[1]);

   if(was_sleeping && is_awakening)
     {
      //--- Directional filter using Awesome Oscillator
      bool is_bullish = ao_buffer[0] > 0;
      bool is_bearish = ao_buffer[0] < 0;

      //--- Buy Signal
      if(is_bullish && !is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "Gator Awakening Buy");
        }

      //--- Sell Signal
      if(is_bearish && !is_trade_open)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "Gator Awakening Sell");
        }
     }
  }
//+------------------------------------------------------------------+
