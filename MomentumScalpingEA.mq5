//+------------------------------------------------------------------+
//|                                           MomentumScalpingEA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- input parameters
input int                FastEMAPeriod = 12;     // Fast EMA Period
input int                SlowEMAPeriod = 26;     // Slow EMA Period
input int                SignalSMAPeriod = 9;    // Signal SMA Period
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE; // Applied Price
input double             LotSize = 0.01;         // Lot Size
input int                StopLossPips = 15;      // Stop Loss in Pips
input int                TakeProfitPips = 20;    // Take Profit in Pips
input int                MagicNumber = 87654;    // Magic Number

//--- global variables
CTrade  trade;
int     macd_handle;
double  main_buffer[2];
double  signal_buffer[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create trade instance
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();

//--- get MACD handle
   macd_handle = iMACD(_Symbol, _Period, FastEMAPeriod, SlowEMAPeriod, SignalSMAPeriod, AppliedPrice);

   if(macd_handle == INVALID_HANDLE)
     {
      printf("Error creating MACD indicator");
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
   IndicatorRelease(macd_handle);
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

//--- get MACD values for the last 2 completed bars
   if(CopyBuffer(macd_handle, 0, 1, 2, main_buffer) != 2 ||   // Main Line
      CopyBuffer(macd_handle, 1, 1, 2, signal_buffer) != 2)  // Signal Line
     {
      printf("Error copying MACD buffer");
      return;
     }

//--- check for existing position for this symbol and magic number
   long position_type = 0; // 0 = no position, 1 = buy, -1 = sell
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         position_type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         break;
        }
     }

//--- Trading logic
// buffer[1] = value on the bar before the most recently completed bar
// buffer[0] = value on the most recently completed bar

//--- check for buy signal (MACD Main Line crosses above Signal Line)
   if(main_buffer[1] <= signal_buffer[1] && main_buffer[0] > signal_buffer[0])
     {
      // If a sell position is open, close it (reversal)
      if(position_type == -1)
        {
         trade.PositionClose(_Symbol);
         position_type = 0;
        }
      // If no position is open, open a buy
      if(position_type == 0)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = price - StopLossPips * _Point;
         double tp = price + TakeProfitPips * _Point;
         trade.Buy(LotSize, _Symbol, price, sl, tp, "MACD Buy Signal");
        }
     }

//--- check for sell signal (MACD Main Line crosses below Signal Line)
   if(main_buffer[1] >= signal_buffer[1] && main_buffer[0] < signal_buffer[0])
     {
      // If a buy position is open, close it (reversal)
      if(position_type == 1)
        {
         trade.PositionClose(_Symbol);
         position_type = 0;
        }
      // If no position is open, open a sell
      if(position_type == 0)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = price + StopLossPips * _Point;
         double tp = price - TakeProfitPips * _Point;
         trade.Sell(LotSize, _Symbol, price, sl, tp, "MACD Sell Signal");
        }
     }
  }
//+------------------------------------------------------------------+
