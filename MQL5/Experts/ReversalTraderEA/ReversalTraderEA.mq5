//+------------------------------------------------------------------+
//|                                             ReversalTraderEA.mq5 |
//|                      Copyright 2023, Your Name (Jules)           |
//|                                      https://www.example.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name (Jules)"
#property link      "https://www.example.com"
#property version   "1.00"
#property description "Expert Advisor for reversal trading using RSI, Aroon, and Zigzag."

#include <Trade/Trade.mqh>

//--- Input Parameters
input group "Trade Settings"
input double InpLotSize = 0.01;            // Lot Size
input int    InpStopLoss = 500;            // Stop Loss (in points)
input int    InpTakeProfit = 1000;         // Take Profit (in points)
input ulong  InpMagicNumber = 12345;       // Magic Number
input int    InpRiskRewardRatio = 2;       // Risk:Reward Ratio for TP

input group "RSI Settings"
input int    InpRsiPeriod = 14;            // RSI Period
input int    InpRsiOverbought = 70;        // RSI Overbought Level
input int    InpRsiOversold = 30;          // RSI Oversold Level
input bool   InpEnableDivergence = true;   // Enable RSI Divergence Check

input group "Aroon Settings"
input int    InpAroonPeriod = 25;          // Aroon Period
input int    InpAroonTriggerLevel = 70;    // Aroon Trigger Level

input group "Zigzag Settings"
input int    InpZigzagDepth = 12;          // Zigzag Depth
input int    InpZigzagDeviation = 5;       // Zigzag Deviation
input int    InpZigzagBackstep = 3;        // Zigzag Backstep

//--- Global variables
CTrade trade;
int rsi_handle;
int aroon_handle;
int zigzag_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize CTrade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);

    //--- Initialize Indicators
    rsi_handle = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
    if(rsi_handle == INVALID_HANDLE)
    {
        printf("Error creating RSI indicator");
        return(INIT_FAILED);
    }

    aroon_handle = iAroon(_Symbol, _Period, InpAroonPeriod);
    if(aroon_handle == INVALID_HANDLE)
    {
        printf("Error creating Aroon indicator");
        return(INIT_FAILED);
    }

    // Zigzag is a custom indicator
    zigzag_handle = iCustom(_Symbol, _Period, "Indicators\\Examples\\ZigZag", InpZigzagDepth, InpZigzagDeviation, InpZigzagBackstep);
    if(zigzag_handle == INVALID_HANDLE)
    {
        printf("Error creating Zigzag indicator");
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    IndicatorRelease(rsi_handle);
    IndicatorRelease(aroon_handle);
    IndicatorRelease(zigzag_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check for new bar to avoid trading on every tick
    static datetime last_bar_time;
    if(last_bar_time == Time[0])
        return;
    last_bar_time = Time[0];

    //--- Check if we already have an open position for this symbol
    if(PositionSelect(_Symbol))
    {
        return;
    }

    //--- Get indicator values
    double rsi_values[3];
    double aroon_up[3];
    double aroon_down[3];

    if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_values) < 3 ||
       CopyBuffer(aroon_handle, 0, 0, 3, aroon_up) < 3 ||
       CopyBuffer(aroon_handle, 1, 0, 3, aroon_down) < 3)
    {
        printf("Error copying indicator buffers");
        return;
    }

    //--- Check for trading signals
    CheckBuySignal(rsi_values, aroon_up, aroon_down);
    CheckSellSignal(rsi_values, aroon_up, aroon_down);
}

//+------------------------------------------------------------------+
//| Check for a Buy Signal                                           |
//+------------------------------------------------------------------+
void CheckBuySignal(const double &rsi[], const double &aroon_up[], const double &aroon_down[])
{
    //--- Basic Conditions
    bool rsi_oversold = rsi[1] < InpRsiOversold;
    bool aroon_bullish = aroon_up[1] > aroon_down[1] || aroon_up[1] > InpAroonTriggerLevel;

    //--- Divergence Condition
    bool bullish_divergence = InpEnableDivergence && CheckBullishDivergence(100);

    if (aroon_bullish && (rsi_oversold || bullish_divergence))
    {
        double last_swing_low = GetLastZigzagLow();
        if (last_swing_low > 0 && last_swing_low < Close[1])
        {
            //--- Confluence confirmed, open buy trade
            double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double stop_loss = last_swing_low;
            double take_profit = entry_price + (entry_price - stop_loss) * InpRiskRewardRatio;

            Print("BUY SIGNAL: RSI Oversold/Divergence, Aroon Bullish, Zigzag Low confirmed.");
            trade.Buy(InpLotSize, _Symbol, entry_price, stop_loss, take_profit, "Buy triggered by RAZ Strategy");
        }
    }
}

//+------------------------------------------------------------------+
//| Check for a Sell Signal                                          |
//+------------------------------------------------------------------+
void CheckSellSignal(const double &rsi[], const double &aroon_up[], const double &aroon_down[])
{
    //--- Basic Conditions
    bool rsi_overbought = rsi[1] > InpRsiOverbought;
    bool aroon_bearish = aroon_down[1] > aroon_up[1] || aroon_down[1] > InpAroonTriggerLevel;

    //--- Divergence Condition
    bool bearish_divergence = InpEnableDivergence && CheckBearishDivergence(100);

    if (aroon_bearish && (rsi_overbought || bearish_divergence))
    {
        double last_swing_high = GetLastZigzagHigh();
        if (last_swing_high > 0 && last_swing_high > Close[1])
        {
            //--- Confluence confirmed, open sell trade
            double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double stop_loss = last_swing_high;
            double take_profit = entry_price - (stop_loss - entry_price) * InpRiskRewardRatio;

            Print("SELL SIGNAL: RSI Overbought/Divergence, Aroon Bearish, Zigzag High confirmed.");
            trade.Sell(InpLotSize, _Symbol, entry_price, stop_loss, take_profit, "Sell triggered by RAZ Strategy");
        }
    }
}

//+------------------------------------------------------------------+
//| Get the price of the last Zigzag swing low                       |
//+------------------------------------------------------------------+
double GetLastZigzagLow()
{
    double zigzag_buffer[3]; // We look for the last 3 points
    // Copy the last 200 bars of Zigzag data, as it's sparse
    if (CopyBuffer(zigzag_handle, 0, 0, 200, zigzag_buffer) <= 0) return 0;

    for (int i = 1; i < 200; i++) // Start from 1 to ignore current incomplete bar
    {
        if (zigzag_buffer[i] > 0)
        {
            // To be a swing low, it must be lower than the point before it
            // This requires finding the *previous* zigzag point, which is complex.
            // A simpler check: is the point a low price?
            if(zigzag_buffer[i] == Low[i])
            {
               // Check if the previous non-empty zigzag point was higher
               for(int j=i+1; j<200; j++) {
                  if(zigzag_buffer[j] > 0) {
                     if(zigzag_buffer[j] > zigzag_buffer[i]) return zigzag_buffer[i];
                     else break; // not a swing low
                  }
               }
            }
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Get the price of the last Zigzag swing high                      |
//+------------------------------------------------------------------+
double GetLastZigzagHigh()
{
    double zigzag_buffer[200];
    if (CopyBuffer(zigzag_handle, 0, 0, 200, zigzag_buffer) <= 0) return 0;

    for (int i = 1; i < 200; i++)
    {
        if (zigzag_buffer[i] > 0)
        {
            // To be a swing high, it must be a high price
            if(zigzag_buffer[i] == High[i])
            {
               // Check if the previous non-empty zigzag point was lower
               for(int j=i+1; j<200; j++) {
                  if(zigzag_buffer[j] > 0) {
                     if(zigzag_buffer[j] < zigzag_buffer[i]) return zigzag_buffer[i];
                     else break; // not a swing high
                  }
               }
            }
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Check for Bullish RSI Divergence                                 |
//+------------------------------------------------------------------+
bool CheckBullishDivergence(int lookback)
{
    int low_idx_1 = -1, low_idx_2 = -1;

    // Find the most recent low (1)
    low_idx_1 = iLowest(_Symbol, _Period, MODE_LOW, lookback, 1);

    // Find the previous low (2)
    low_idx_2 = iLowest(_Symbol, _Period, MODE_LOW, lookback, low_idx_1 + 1);

    if(low_idx_1 < 0 || low_idx_2 < 0) return false;

    // Price made a lower low
    if(Low[low_idx_1] < Low[low_idx_2])
    {
        double rsi_values[lookback+1];
        if(CopyBuffer(rsi_handle, 0, 0, lookback+1, rsi_values) < lookback+1) return false;

        // RSI made a higher low
        if(rsi_values[low_idx_1] > rsi_values[low_idx_2])
        {
            Print("Bullish Divergence detected: Price LL, RSI HL");
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check for Bearish RSI Divergence                                 |
//+------------------------------------------------------------------+
bool CheckBearishDivergence(int lookback)
{
    int high_idx_1 = -1, high_idx_2 = -1;

    // Find the most recent high (1)
    high_idx_1 = iHighest(_Symbol, _Period, MODE_HIGH, lookback, 1);

    // Find the previous high (2)
    high_idx_2 = iHighest(_Symbol, _Period, MODE_HIGH, lookback, high_idx_1 + 1);

    if(high_idx_1 < 0 || high_idx_2 < 0) return false;

    // Price made a higher high
    if(High[high_idx_1] > High[high_idx_2])
    {
        double rsi_values[lookback+1];
        if(CopyBuffer(rsi_handle, 0, 0, lookback+1, rsi_values) < lookback+1) return false;

        // RSI made a lower high
        if(rsi_values[high_idx_1] < rsi_values[high_idx_2])
        {
            Print("Bearish Divergence detected: Price HH, RSI LH");
            return true;
        }
    }
    return false;
}
//+------------------------------------------------------------------+
