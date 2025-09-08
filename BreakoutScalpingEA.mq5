//+------------------------------------------------------------------+
//|                                           BreakoutScalpingEA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                breakout_period      = 20;    // Period for breakout channel
input bool               use_volume_confirm   = true;  // Use volume confirmation
input double             volume_factor        = 1.5;   // Volume must be this much > average
input double             lot_size             = 0.01;  // Lot Size
input int                take_profit_pips     = 20;    // Take Profit in Pips
input int                sl_buffer_pips       = 2;     // Buffer for dynamic SL (in pips)
input int                magic_number         = 54321; // Magic Number

//--- global variables
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(magic_number);
   trade.SetMarginMode();
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
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

//--- Do not open a new trade if one is already open
   if(PositionsTotal() > 0)
     {
      // A more robust check would be to check the magic number, but for this EA we assume one trade at a time.
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic_number)
           {
            return;
           }
        }
     }

//--- Get historical data to find the channel and breakout
   MqlRates rates[];
   int bars_to_copy = breakout_period + 2; // +1 for the signal bar, +1 for the start of the channel
   if(CopyRates(_Symbol, _Period, 0, bars_to_copy, rates) < bars_to_copy)
     {
      printf("Error copying rates data, not enough bars.");
      return;
     }

//--- Find the highest high and lowest low of the channel period (from index 2 to breakout_period+1)
   double highest_high = rates[2].high;
   double lowest_low = rates[2].low;
   long total_volume = rates[2].tick_volume;
   for(int i = 3; i < bars_to_copy; i++)
     {
      if(rates[i].high > highest_high)
        {
         highest_high = rates[i].high;
        }
      if(rates[i].low < lowest_low)
        {
         lowest_low = rates[i].low;
        }
      total_volume += rates[i].tick_volume;
     }

//--- The breakout candle is the most recently completed bar (index 1)
   MqlRates signal_candle = rates[1];

//--- Check for breakout
   bool buy_breakout = signal_candle.high > highest_high;
   bool sell_breakout = signal_candle.low < lowest_low;

   if(!buy_breakout && !sell_breakout)
     {
      return; // No breakout occurred
     }

//--- Volume Confirmation
   if(use_volume_confirm)
     {
      double avg_volume = (double)total_volume / breakout_period;
      if(signal_candle.tick_volume < avg_volume * volume_factor)
        {
         return; // Volume does not confirm breakout
        }
     }

//--- Execute Trade
   if(buy_breakout)
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = highest_high - sl_buffer_pips * _Point; // Set SL just below the broken resistance
      double tp = price + take_profit_pips * _Point;
      trade.Buy(lot_size, _Symbol, price, sl, tp, "Breakout Buy");
     }
   else if(sell_breakout)
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = lowest_low + sl_buffer_pips * _Point; // Set SL just above the broken support
      double tp = price - take_profit_pips * _Point;
      trade.Sell(lot_size, _Symbol, price, sl, tp, "Breakout Sell");
     }
  }
//+------------------------------------------------------------------+
