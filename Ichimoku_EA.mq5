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

//--- Multi-Timeframe Filter Settings
input bool               UseMultiTimeframeFilter = true;   // Enable Multi-Timeframe Confirmation
input ENUM_TIMEFRAMES    HigherTimeframe = PERIOD_H4;    // Higher Timeframe for Trend Confirmation

//--- Stop Loss & Trailing Stop Settings
input bool               UseDynamicStop = true;          // Use Dynamic Stop Loss (based on Kijun-sen)
input bool               UseTrailingStop = true;         // Use Kijun-sen as a Trailing Stop
input int                StopLossOffsetPips = 10;        // Offset for SL from the Kijun-sen (in Pips)

//--- global variables
CTrade  trade;
int     ichimoku_handle;
int     ichimoku_handle_htf;  // Handle for the higher timeframe Ichimoku
double  tenkan_buffer[];      // Buffer for Tenkan-sen
double  kijun_buffer[];       // Buffer for Kijun-sen
double  senkou_a_buffer[];    // Buffer for Senkou Span A
double  senkou_b_buffer[];    // Buffer for Senkou Span B
double  close_buffer[];       // Buffer for Close prices

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- resize buffers
   ArrayResize(tenkan_buffer, 2);
   ArrayResize(kijun_buffer, 2);
   ArrayResize(senkou_a_buffer, 2);
   ArrayResize(senkou_b_buffer, 2);
   if(ArrayResize(close_buffer, KijunSen + 2) != KijunSen + 2)
     {
      printf("Error resizing close_buffer array! KijunSen=%d", KijunSen);
      return(INIT_FAILED);
     }

//--- get Ichimoku handle
   ichimoku_handle = iIchimoku(_Symbol, _Period, TenkanSen, KijunSen, SenkouSpanB);

   if(ichimoku_handle == INVALID_HANDLE)
     {
      printf("Error creating Ichimoku indicator for the current timeframe");
      return(INIT_FAILED);
     }

//--- get Ichimoku handle for higher timeframe
   if(UseMultiTimeframeFilter)
     {
      ichimoku_handle_htf = iIchimoku(_Symbol, HigherTimeframe, TenkanSen, KijunSen, SenkouSpanB);
      if(ichimoku_handle_htf == INVALID_HANDLE)
        {
         printf("Error creating Ichimoku indicator for the higher timeframe %s", EnumToString(HigherTimeframe));
         return(INIT_FAILED);
        }
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
   IndicatorRelease(ichimoku_handle);
   if(UseMultiTimeframeFilter)
     {
      IndicatorRelease(ichimoku_handle_htf);
     }
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- TRADE MANAGEMENT (runs on every tick) ---
// This section is for managing existing trades, like trailing stops.
   ManageTrailingStop();

//--- NEW TRADE LOGIC (runs once per bar) ---
// This section checks for new trade opportunities.
   static datetime last_bar_time = 0;
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   if(current_bar_time == last_bar_time)
     {
      return; // Not a new bar, do nothing more on this tick
     }
   last_bar_time = current_bar_time;

//--- get Ichimoku and price values for the last completed bars
   if(CopyBuffer(ichimoku_handle, 0, 1, 2, tenkan_buffer) != 2 ||      // Tenkan-sen
      CopyBuffer(ichimoku_handle, 1, 1, 2, kijun_buffer) != 2 ||       // Kijun-sen
      CopyBuffer(ichimoku_handle, 2, 1, 2, senkou_a_buffer) != 2 ||    // Senkou Span A
      CopyBuffer(ichimoku_handle, 3, 1, 2, senkou_b_buffer) != 2 ||    // Senkou Span B
      CopyClose(_Symbol, _Period, 1, KijunSen + 2, close_buffer) != (KijunSen + 2))
     {
      printf("Error copying indicator/price buffers for new trade check.");
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

//--- Trading Strategy ---
// The strategy requires three confirmations for a trade:
// 1. Kumo Breakout: The price must close above/below the Kumo cloud.
// 2. Tenkan/Kijun Cross: The Tenkan-sen must be above/below the Kijun-sen.
// 3. Chikou Span Filter: The Chikou span must be above/below the price KijunSen periods ago.

// Note on buffer indexing: CopyBuffer starting from bar 1 places the most recently completed bar's data at index 0.
// buffer[0] = value on the most recently completed bar (bar index 1)
// buffer[1] = value on the bar before that (bar index 2)
// close_buffer[KijunSen] = close price from KijunSen bars before the most recently completed one (bar index 1 + KijunSen)

//--- Define cloud boundaries for the last two completed bars
   double cloud_top_curr = fmax(senkou_a_buffer[0], senkou_b_buffer[0]);
   double cloud_bottom_curr = fmin(senkou_a_buffer[0], senkou_b_buffer[0]);
   double cloud_top_prev = fmax(senkou_a_buffer[1], senkou_b_buffer[1]);
   double cloud_bottom_prev = fmin(senkou_a_buffer[1], senkou_b_buffer[1]);

//--- Define Bullish Conditions
   bool buy_kumo_breakout = close_buffer[1] <= cloud_top_prev && close_buffer[0] > cloud_top_curr;
   bool buy_tenkan_above_kijun = tenkan_buffer[0] > kijun_buffer[0];
   bool buy_chikou_filter = close_buffer[0] > close_buffer[KijunSen];

//--- Check for Strong Buy Signal (All conditions must be met)
   if(buy_kumo_breakout && buy_tenkan_above_kijun && buy_chikou_filter)
     {
      if(!is_trade_open && IsHigherTimeframeAligned(true))
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double tp = price + TakeProfitPips * _Point;
         double sl = 0;

         //--- Calculate Stop Loss
         if(UseDynamicStop)
           {
            // Dynamic SL: Kijun-sen value from the last completed bar, plus an offset.
            sl = kijun_buffer[0] - StopLossOffsetPips * _Point;
           }
         else
           {
            // Fixed SL: Based on input pips.
            sl = price - StopLossPips * _Point;
           }

         //--- Zero out SL/TP if their corresponding pip inputs are 0
         if(StopLossPips == 0 && !UseDynamicStop) sl = 0;
         if(TakeProfitPips == 0) tp = 0;

         trade.Buy(LotSize, _Symbol, price, sl, tp, "Ichimoku Strong Buy");
        }
     }

//--- Define Bearish Conditions
   bool sell_kumo_breakout = close_buffer[1] >= cloud_bottom_prev && close_buffer[0] < cloud_bottom_curr;
   bool sell_tenkan_below_kijun = tenkan_buffer[0] < kijun_buffer[0];
   bool sell_chikou_filter = close_buffer[0] < close_buffer[KijunSen];

//--- Check for Strong Sell Signal (All conditions must be met)
   if(sell_kumo_breakout && sell_tenkan_below_kijun && sell_chikou_filter)
     {
      if(!is_trade_open && IsHigherTimeframeAligned(false))
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double tp = price - TakeProfitPips * _Point;
         double sl = 0;

         //--- Calculate Stop Loss
         if(UseDynamicStop)
           {
            // Dynamic SL: Kijun-sen value from the last completed bar, plus an offset.
            sl = kijun_buffer[0] + StopLossOffsetPips * _Point;
           }
         else
           {
            // Fixed SL: Based on input pips.
            sl = price + StopLossPips * _Point;
           }

         //--- Zero out SL/TP if their corresponding pip inputs are 0
         if(StopLossPips == 0 && !UseDynamicStop) sl = 0;
         if(TakeProfitPips == 0) tp = 0;

         trade.Sell(LotSize, _Symbol, price, sl, tp, "Ichimoku Strong Sell");
        }
     }
  }
//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   if(!UseTrailingStop)
      return;

//--- We need the current Kijun-sen value (from bar 0)
   double kijun_arr[1];
   if(CopyBuffer(ichimoku_handle, 1, 0, 1, kijun_arr) != 1)
     {
      // Don't flood log with errors, just exit if data is not ready
      return;
     }
   double current_kijun = kijun_arr[0];
   if(current_kijun == 0) // Kijun might be 0 if indicator is still calculating
      return;

//--- Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         double new_sl = 0;
         double current_sl = PositionGetDouble(POSITION_SL);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         long position_type = PositionGetInteger(POSITION_TYPE);

         if(position_type == POSITION_TYPE_BUY)
           {
            new_sl = NormalizeDouble(current_kijun - StopLossOffsetPips * _Point, _Digits);
            // New SL must be higher than current SL, and also above open price to be profitable
            if(new_sl > open_price && new_sl > current_sl)
              {
               trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
              }
           }
         else if(position_type == POSITION_TYPE_SELL)
           {
            new_sl = NormalizeDouble(current_kijun + StopLossOffsetPips * _Point, _Digits);
            // New SL must be lower than current SL (and not 0), and also below open price
            if(new_sl < open_price && (new_sl < current_sl || current_sl == 0))
              {
               trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
              }
           }
        }
     }
  }

bool IsHigherTimeframeAligned(bool is_buy_signal)
  {
//--- If the filter is disabled, the alignment is always true
   if(!UseMultiTimeframeFilter)
      return(true);

//--- Buffers for HTF data
   double htf_close[2];
   double htf_senkou_a[2];
   double htf_senkou_b[2];

//--- Copy data for the last completed bar on the higher timeframe
   if(CopyClose(_Symbol, HigherTimeframe, 1, 2, htf_close) != 2 ||
      CopyBuffer(ichimoku_handle_htf, 2, 1, 2, htf_senkou_a) != 2 ||
      CopyBuffer(ichimoku_handle_htf, 3, 1, 2, htf_senkou_b) != 2)
     {
      printf("Error copying HTF indicator data for %s. Skipping trade check.", _Symbol);
      return(false); // Fail safe, do not trade
     }

//--- Determine HTF cloud boundaries and close price
   double htf_cloud_top = fmax(htf_senkou_a[0], htf_senkou_b[0]);
   double htf_cloud_bottom = fmin(htf_senkou_a[0], htf_senkou_b[0]);
   double htf_price_close = htf_close[0];

   if(is_buy_signal)
     {
      //--- For a buy signal, we need the HTF to be bullish (price above cloud)
      return(htf_price_close > htf_cloud_top);
     }
   else // is_sell_signal
     {
      //--- For a sell signal, we need the HTF to be bearish (price below cloud)
      return(htf_price_close < htf_cloud_bottom);
     }
  }
//+------------------------------------------------------------------+
