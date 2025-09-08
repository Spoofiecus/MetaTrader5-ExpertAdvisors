//+------------------------------------------------------------------+
//|                                              RangeScalpingEA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                BandsPeriod = 20;       // Bollinger Bands Period
input double             BandsDeviation = 2.0;   // Bollinger Bands Deviation
input int                BandsShift = 0;         // Bollinger Bands Shift
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE; // Applied Price
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 20;      // Stop Loss in Pips
input int                MagicNumber = 76543;    // Magic Number

//--- global variables
CTrade  trade;
int     bands_handle;
// We only need buffers for the most recent bar for exits, and the previous bar for entries.
double  upper_band_buffer[2];
double  lower_band_buffer[2];
double  high_buffer[2];
double  low_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get Bollinger Bands handle
   bands_handle = iBands(_Symbol, _Period, BandsPeriod, BandsShift, BandsDeviation, AppliedPrice);

   if(bands_handle == INVALID_HANDLE)
     {
      printf("Error creating Bollinger Bands indicator");
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
   IndicatorRelease(bands_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Get current prices
   double current_high = SymbolInfoDouble(_Symbol, SYMBOL_HIGH);
   double current_low = SymbolInfoDouble(_Symbol, SYMBOL_LOW);

//--- Get Bollinger Bands values for the current (0) and previous (1) bars
   if(CopyBuffer(bands_handle, 1, 0, 2, upper_band_buffer) != 2 || // Upper Band
      CopyBuffer(bands_handle, 2, 0, 2, lower_band_buffer) != 2)   // Lower Band
     {
      printf("Error copying Bollinger Bands buffer");
      return;
     }

//--- Check for an open position and its type
   long position_type = 0; // 0 = no position, 1 = buy, -1 = sell
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         position_type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         break;
        }
     }

//--- Dynamic Exit Logic (runs on every tick)
   if(position_type == 1) // Buy position is open
     {
      // Close if price hits the upper band
      if(current_high >= upper_band_buffer[0])
        {
         trade.PositionClose(_Symbol);
         return; // Exit after closing to avoid re-entry on the same tick
        }
     }
   else if(position_type == -1) // Sell position is open
     {
      // Close if price hits the lower band
      if(current_low <= lower_band_buffer[0])
        {
         trade.PositionClose(_Symbol);
         return; // Exit after closing
        }
     }

//--- Entry Logic (runs only once per bar)
   static datetime last_bar_time = 0;
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(current_bar_time == last_bar_time)
     {
      return; // Not a new bar, do not check for new entries
     }
   last_bar_time = current_bar_time;

//--- If we have reached here, it means it's a new bar and no position was closed on this tick.
//--- We check for entry signals only if no trade is currently open.
   if(position_type == 0)
     {
      // Get price data for the last completed bar (index 1)
      if(CopyHigh(_Symbol, _Period, 1, 1, high_buffer) != 1 ||
         CopyLow(_Symbol, _Period, 1, 1, low_buffer) != 1)
        {
         printf("Error copying price data for entry signal");
         return;
        }

      // Check for Buy signal (price touched lower band on the previous bar)
      if(low_buffer[0] <= lower_band_buffer[1])
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         trade.Buy(LotSize, _Symbol, price, sl, 0, "Range Scalp Buy");
        }
      // Check for Sell signal (price touched upper band on the previous bar)
      else if(high_buffer[0] >= upper_band_buffer[1])
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         trade.Sell(LotSize, _Symbol, price, sl, 0, "Range Scalp Sell");
        }
     }
  }
//+------------------------------------------------------------------+
