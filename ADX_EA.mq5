//+------------------------------------------------------------------+
//|                                                       ADX_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                ADXPeriod = 14;         // ADX Period
input int                ADXThreshold = 25;      // ADX Trend Strength Threshold
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 50;      // Stop Loss in Pips
input int                TakeProfitPips = 100;   // Take Profit in Pips
input int                TrailingStopPips = 30;  // Trailing Stop in Pips
input bool               CloseOnOppositeSignal = true; // Close on opposite signal
input bool               EnableTimeFilter = false; // Enable Trading Time Filter
input int                TradingHourStart = 8;     // Trading start hour (server time)
input int                TradingHourEnd   = 17;    // Trading end hour (server time)
input int                MagicNumber = 210938;   // Magic Number

//--- global variables
CTrade  trade;
int     adx_handle;
double  adx_main_buffer[2];
double  plus_di_buffer[2];
double  minus_di_buffer[2];

//+------------------------------------------------------------------+
//| Trailing Stop Function                                           |
//+------------------------------------------------------------------+
void TrailingStop(int trailingStopPips)
  {
   if(trailingStopPips <= 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         if(PositionSelectByTicket(ticket))
           {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP);
            double current_price;
            double new_sl;

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
              {
               current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               new_sl = current_price - trailingStopPips * _Point;
               if(current_price > open_price + trailingStopPips * _Point && (new_sl > current_sl || current_sl == 0))
                 {
                  trade.PositionModify(ticket, new_sl, current_tp);
                 }
              }
            else // POSITION_TYPE_SELL
              {
               current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               new_sl = current_price + trailingStopPips * _Point;
               if(current_price < open_price - trailingStopPips * _Point && (new_sl < current_sl || current_sl == 0))
                 {
                  trade.PositionModify(ticket, new_sl, current_tp);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get ADX handle
   adx_handle = iADX(_Symbol, _Period, ADXPeriod);

   if(adx_handle == INVALID_HANDLE)
     {
      printf("Error creating ADX indicator");
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
   IndicatorRelease(adx_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- handle trailing stop on every tick
   TrailingStop(TrailingStopPips);

//--- static variable to store the bar time. This ensures the logic runs only once per bar.
   static datetime last_bar_time = 0;
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   if(current_bar_time == last_bar_time)
     {
      return; // Not a new bar, do nothing
     }
   last_bar_time = current_bar_time;

//--- Time Filter Check
   if(EnableTimeFilter)
     {
      MqlDateTime time_struct;
      TimeCurrent(time_struct);
      int current_hour = time_struct.hour;

      if(TradingHourStart < TradingHourEnd) // Normal non-overnight session
        {
         if(current_hour < TradingHourStart || current_hour >= TradingHourEnd)
            return;
        }
      else // Overnight session (e.g., 22:00-05:00)
        {
         if(current_hour < TradingHourStart && current_hour >= TradingHourEnd)
            return;
        }
     }

//--- get ADX values for the last 2 completed bars
   if(CopyBuffer(adx_handle, 0, 1, 2, adx_main_buffer) != 2 || // Main ADX Line
      CopyBuffer(adx_handle, 1, 1, 2, plus_di_buffer) != 2 ||  // +DI Line
      CopyBuffer(adx_handle, 2, 1, 2, minus_di_buffer) != 2)   // -DI Line
     {
      printf("Error copying ADX buffers");
      return;
     }

//--- check for open positions for this symbol and magic number
   long open_position_ticket = 0;
   long open_position_type = -1; // -1: none, POSITION_TYPE_BUY: buy, POSITION_TYPE_SELL: sell

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         open_position_ticket = (long)PositionGetTicket(i);
         open_position_type = PositionGetInteger(POSITION_TYPE);
         break;
        }
     }

//--- Trading logic
// buffer[1] = value on the bar before the most recently completed bar
// buffer[0] = value on the most recently completed bar

//--- check for buy signal (+DI crosses above -DI and ADX is strong)
   if(plus_di_buffer[1] <= minus_di_buffer[1] && plus_di_buffer[0] > minus_di_buffer[0] && adx_main_buffer[0] > ADXThreshold)
     {
      // If we are allowed to close on opposite signal and a sell trade is open, close it.
      if(CloseOnOppositeSignal && open_position_type == POSITION_TYPE_SELL)
        {
         trade.PositionClose(open_position_ticket);
         open_position_ticket = 0;
         open_position_type = -1;
        }

      // If no trade is open, open a new buy trade.
      if(open_position_ticket == 0)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "ADX Buy Signal");
        }
     }

//--- check for sell signal (-DI crosses above +DI and ADX is strong)
   if(minus_di_buffer[1] <= plus_di_buffer[1] && minus_di_buffer[0] > plus_di_buffer[0] && adx_main_buffer[0] > ADXThreshold)
     {
      // If we are allowed to close on opposite signal and a buy trade is open, close it.
      if(CloseOnOppositeSignal && open_position_type == POSITION_TYPE_BUY)
        {
         trade.PositionClose(open_position_ticket);
         open_position_ticket = 0;
         open_position_type = -1;
        }

      // If no trade is open, open a new sell trade.
      if(open_position_ticket == 0)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         if(StopLossPips == 0) sl = 0;
         if(TakeProfitPips == 0) tp = 0;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "ADX Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
