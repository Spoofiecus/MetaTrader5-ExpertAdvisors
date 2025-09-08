// MQL5 Expert Advisor for the Moving Average Crossover with Retracement Strategy
// Coded by Jules

#property copyright "User"
#property link      "https://github.com/Jules"
#property version   "1.0"
#property description "Trades pullbacks to an EMA ribbon in a trending market."

//+------------------------------------------------------------------+
//| Include Trade Library                                            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| EA Inputs                                                        |
//+------------------------------------------------------------------+
//--- MA Ribbon Settings
sinput group                 "Moving Average Ribbon Settings"
input int                    inp_ema_fast_period    = 5;           // Fast EMA Period
input int                    inp_ema_medium_period  = 8;           // Medium EMA Period
input int                    inp_ema_slow_period    = 13;          // Slow EMA Period

//--- Risk Management & Exit
sinput group                 "Risk Management"
input double                 inp_lots               = 0.01;        // Trade Lot Size
input double                 inp_tp_pips            = 10.0;        // Take Profit (Pips)
input double                 inp_sl_buffer_pips     = 2.0;         // SL Buffer (Pips) from Candle High/Low

//--- EA Management
sinput group                 "EA Management"
input ulong                  inp_magic_number       = 65432;       // EA Magic Number
input string                 inp_comment            = "MACross";   // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade          g_trade;
int             g_ema_fast_handle;
int             g_ema_medium_handle;
int             g_ema_slow_handle;

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
void CheckAndManageTrade();
void ExecuteBuy(const MqlRates &entry_candle);
void ExecuteSell(const MqlRates &entry_candle);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize trade object
   g_trade.SetExpertMagicNumber(inp_magic_number);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

//--- Get Fast EMA handle
   g_ema_fast_handle=iMA(_Symbol,_Period,inp_ema_fast_period,0,MODE_EMA,PRICE_CLOSE);
   if(g_ema_fast_handle==INVALID_HANDLE)
     {
      Print("Error getting Fast EMA indicator handle. Error: ",GetLastError());
      return(INIT_FAILED);
     }

//--- Get Medium EMA handle
   g_ema_medium_handle=iMA(_Symbol,_Period,inp_ema_medium_period,0,MODE_EMA,PRICE_CLOSE);
   if(g_ema_medium_handle==INVALID_HANDLE)
     {
      Print("Error getting Medium EMA indicator handle. Error: ",GetLastError());
      return(INIT_FAILED);
     }

//--- Get Slow EMA handle
   g_ema_slow_handle=iMA(_Symbol,_Period,inp_ema_slow_period,0,MODE_EMA,PRICE_CLOSE);
   if(g_ema_slow_handle==INVALID_HANDLE)
     {
      Print("Error getting Slow EMA indicator handle. Error: ",GetLastError());
      return(INIT_FAILED);
     }

   Print("MA Crossover Retracement EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   IndicatorRelease(g_ema_fast_handle);
   IndicatorRelease(g_ema_medium_handle);
   IndicatorRelease(g_ema_slow_handle);
   Print("MA Crossover Retracement EA deinitialized.");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Standard new bar check
   static datetime last_bar_time = 0;
   MqlRates rates[];
   if(CopyRates(_Symbol,_Period,0,1,rates)<1) return;
   if(rates[0].time == last_bar_time) return;
   last_bar_time=rates[0].time;

//--- Do not run if a trade is already open
   if(PositionSelect(_Symbol))
     {
      if(PositionGetInteger(POSITION_MAGIC) == inp_magic_number)
         return;
     }

//--- Run the main logic
   CheckAndManageTrade();
  }

//+------------------------------------------------------------------+
//| Main logic function                                              |
//+------------------------------------------------------------------+
void CheckAndManageTrade()
  {
//--- Get latest price and indicator data
   MqlRates rates[3];
   if(CopyRates(_Symbol,_Period,0,3,rates)<3) return;

   double fast_ema[3], medium_ema[3], slow_ema[3];
   if(CopyBuffer(g_ema_fast_handle,0,0,3,fast_ema)<3 ||
      CopyBuffer(g_ema_medium_handle,0,0,3,medium_ema)<3 ||
      CopyBuffer(g_ema_slow_handle,0,0,3,slow_ema)<3)
     {
      return; // Error copying buffers
     }

//--- 1. Trend Determination (on the last closed bar, index 1)
   bool is_uptrend = (fast_ema[1] > medium_ema[1] && medium_ema[1] > slow_ema[1]);
   bool is_downtrend = (fast_ema[1] < medium_ema[1] && medium_ema[1] < slow_ema[1]);

   if(!is_uptrend && !is_downtrend) return; // No clear trend

//--- 2. Entry Pattern Detection
   bool buy_setup = false;
   if(is_uptrend)
     {
      // Pullback: Bar[2]'s low touched or went below the fast EMA
      bool pullback = rates[2].low <= fast_ema[2];
      // Recovery: Bar[1] closed back above the fast EMA
      bool recovery = rates[1].close > fast_ema[1] && rates[1].open <= fast_ema[1];
      if(pullback && recovery)
        {
         buy_setup=true;
        }
     }

   bool sell_setup = false;
   if(is_downtrend)
     {
      // Pullback: Bar[2]'s high touched or went above the fast EMA
      bool pullback = rates[2].high >= fast_ema[2];
      // Recovery: Bar[1] closed back below the fast EMA
      bool recovery = rates[1].close < fast_ema[1] && rates[1].open >= fast_ema[1];
      if(pullback && recovery)
        {
         sell_setup=true;
        }
     }

//--- If a setup is found, execute the trade
   if(buy_setup)
     {
      ExecuteBuy(rates[1]);
     }
   else if(sell_setup)
     {
      ExecuteSell(rates[1]);
     }
  }

//+------------------------------------------------------------------+
//| Executes a Buy Trade                                             |
//+------------------------------------------------------------------+
void ExecuteBuy(const MqlRates &entry_candle)
  {
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl = entry_candle.low - inp_sl_buffer_pips * (_Point * 10.0);
   double tp = price + inp_tp_pips * (_Point * 10.0);

   if(!g_trade.Buy(inp_lots,_Symbol,price,sl,tp,inp_comment))
     {
      Print("Buy order execution failed. Error: ",g_trade.ResultRetcode(),". Message: ",g_trade.ResultComment());
     }
   else
     {
      Print("Buy order placed successfully at ", price);
     }
  }

//+------------------------------------------------------------------+
//| Executes a Sell Trade                                            |
//+------------------------------------------------------------------+
void ExecuteSell(const MqlRates &entry_candle)
  {
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = entry_candle.high + inp_sl_buffer_pips * (_Point * 10.0);
   double tp = price - inp_tp_pips * (_Point * 10.0);

   if(!g_trade.Sell(inp_lots,_Symbol,price,sl,tp,inp_comment))
     {
      Print("Sell order execution failed. Error: ",g_trade.ResultRetcode(),". Message: ",g_trade.ResultComment());
     }
   else
     {
      Print("Sell order placed successfully at ", price);
     }
  }
