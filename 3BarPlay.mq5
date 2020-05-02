//+------------------------------------------------------------------+
//|                                                     3BarPlay.mq5 |
//|                                                               JG |
//|                                                             None |
//+------------------------------------------------------------------+
//--- input parameters
input int stopLoss = 64;
input int takeProfit = 113;
input int movingAveragePeriod = 50;
input int expertAdvisorMagicNumber = 12345; // EA Magic Number
input double lotSize = 0.1;                 // Lots to Trade
input double barIntervalThreshold = 6;      // Bar Trade interval

input double mul1=2.5; //Multiplier Value 1
input double mul2=2; //Multiplier Value 2

input double div1=4; //Division Value 1
input double div2=3; //Division Value 2

input int strictRule1=1; //Strict Rule 1
input int strictRule2=1; //Strict Rule 2
input int strictRule3=1; //Strict Rule 3
input int strictRule4=1; //Strict Rule 4

//--- Other parameters
int movingAverageHandler; // handle for our Moving Average indicator
double movingAverages[];  // Dynamic array to hold the values of Moving Average for each bars
int STP, TKP;             // To be used for Stop Loss & Take Profit values

bool positionTakenThisBar = false;
bool isNewBar = false;
string currentTime = "";

bool tradeBarCounterActive = 0;
int barsSinceLastTrade = 0;
int barTradeIntervalThreshold = 0;

int OnInit()
{
  //--- Get the handle for Moving Average indicator
  movingAverageHandler = iMA(_Symbol, _Period, movingAveragePeriod, 0, MODE_EMA, PRICE_CLOSE);

  //--- What if handle returns Invalid Handle
  if (movingAverageHandler < 0)
  {
    Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
  }

  STP = stopLoss;
  TKP = takeProfit;
  barTradeIntervalThreshold = barIntervalThreshold;
  

  //if (_Digits == 5 || _Digits == 3)
  //{
  //  STP = STP * 10;
  //  TKP = TKP * 10;
  //}

  return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
  IndicatorRelease(movingAverageHandler);
}

void OnTick()
{
  //--- Do we have enough bars to work with
  // int Mybars = Bars(_Symbol, _Period);
  // if (Mybars < 60) // if total bars is less than 60 bars
  // {
  //   Alert("We have less than 60 bars, EA will now exit!!");
  //   return;
  // }

  // We will use the static oldTime variable to serve the bar time.
  // At each OnTick execution we will check the current bar time with the saved one.
  // If the bar time isn't equal to the saved time, it indicates that we have a new tick.
  static datetime oldTime;
  datetime newTime[1];

  // copying the last bar time to the element newTime[0]
  int copied = CopyTime(_Symbol, _Period, 0, 1, newTime);
  if (copied > 0) // ok, the data has been copied successfully
  {
    if (oldTime != newTime[0]) // if old time isn't equal to new bar time
    {
      isNewBar = true; // if it isn't a first call, the new bar has appeared
      if (MQL5InfoInteger(MQL5_DEBUGGING))
        Print("We have new bar here ", newTime[0], " old time was ", oldTime);
      oldTime = newTime[0]; // saving bar time
      currentTime = TimeToString(newTime[0], TIME_DATE | TIME_MINUTES);
    }
  }
  else
  {
    Alert("Error in copying historical times data, error =", GetLastError());
    ResetLastError();
    return;
  }

  if (isNewBar == true)
  { 
    if (barsSinceLastTrade > barTradeIntervalThreshold)
    {
      tradeBarCounterActive = false;
      barsSinceLastTrade = 0;
    }
    
    if (tradeBarCounterActive == true)
    {
      barsSinceLastTrade = barsSinceLastTrade + 1;
    }

    positionTakenThisBar = false;
  }

  //--- EA should only check for new trade if we have a new bar
  //if (isNewBar == false)
  //{
  //  return;
  //}

  //--- Define some MQL5 Structures we will use for our trade
  MqlTick latestPriceDetails;   // To be used for getting recent/latest price quotes
  MqlTradeRequest tradeRequest; // To be used for sending our trade requests
  MqlTradeResult tradeResult;   // To be used to get our trade results
  MqlRates barDetails[];        // To be used to store the prices, volumes and spread of each bar
  ZeroMemory(tradeRequest);     // Initialization of tradeRequest structure

  /*
      Let's make sure our arrays values for the Rates and MA values 
      is store serially similar to the timeseries array
      */
  // the bar details arrays
  ArraySetAsSeries(barDetails, true);
  // the MA-8 values arrays
  ArraySetAsSeries(movingAverages, true);

  //--- Get the last price quote using the MQL5 MqlTick Structure
  if (!SymbolInfoTick(_Symbol, latestPriceDetails))
  {
    Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
    return;
  }

  //--- Get the details of the latest 5 bars and MA
  if (CopyRates(_Symbol, _Period, 0, 5, barDetails) < 0)
  {
    Alert("Error copying rates/history data - error:", GetLastError(), "!!");
    return;
  }
  if (CopyBuffer(movingAverageHandler, 0, 0, 5, movingAverages) < 0)
  {
    Alert("Error copying Moving Average indicator buffer - error:", GetLastError());
    return;
  }

  //--- We have no errors, so continue to trading

  //--- Do we have positions opened already? //ToDo: improve this to check more strictly
  bool buy_opened = false;
  bool sell_opened = false;

  if (PositionSelect(_Symbol) == true) // we have an opened position
  {
    if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
      buy_opened = true;
    }
    else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
    {
      sell_opened = true;
    }
  }

  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  int spread = (int)MathRound((ask - bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));

  Comment(
      "Current bar -1 OPEN:" + barDetails[1].open +
      "\nCurrent bar -2 OPEN:" + barDetails[2].open +
      "\nCurrent bar -3 OPEN:" + barDetails[3].open +
      "\n\nCurrent bar -1 CLOSE:" + barDetails[1].close +
      "\nCurrent bar -2 CLOSE:" + barDetails[2].close +
      "\nCurrent bar -3 CLOSE:" + barDetails[3].close +
      "\n\nCurrent bar -1 HIGH:" + barDetails[1].high +
      "\nCurrent bar -2 HIGH:" + barDetails[2].high +
      "\nCurrent bar -3 HIGH:" + barDetails[3].high +
      "\n\nCurrent bar -1 LOW:" + barDetails[1].low +
      "\nCurrent bar -2 LOW:" + barDetails[2].low +
      "\nCurrent bar -3 LOW:" + barDetails[3].low +
      "\n\nCurrent Buy Price:" + ask +
      "\nCurrent Sell Price:" + bid +
      "\n\nCurrent Spread:" + spread);

  // previous price closed above MA-8
  //bool buyCondition1 = (latestPriceDetails.bid > movingAverages[1]);

  if (tradeBarCounterActive == false && positionTakenThisBar == false && CheckForLong3BarPlay(barDetails, ask))
  {
    // any already opened Buy position?
    //if (buy_opened)
    //{
    //  Alert("We already have a Buy Position!!!");
    //  return; // Don't open a new Buy Position
    //}

    tradeResult = MakeLongTrade(tradeRequest, tradeResult, bid, ask);

    if (tradeResult.retcode == 10009 || tradeResult.retcode == 10008) //Request is completed or order placed
    {
      positionTakenThisBar = true;
      tradeBarCounterActive = true;
      Alert("A Buy order at bid price: ", bid, " has been successfully placed with Ticket#:", tradeResult.order, "!!");
    }
    else
    {
      Alert("The Buy order request could not be completed -error:", GetLastError());
      ResetLastError();
      return;
    }
  }

  // previous price closed below MA-8
  //bool sellCondition1 = (latestPriceDetails.ask < movingAverages[1]);

  // bool buyCondition1 = CheckForShort3BarPlay(barDetails);

  // if (sellCondition1 && positionTakenThisBar == false)
  // {
  //   // any already opened Sell position?
  //   //if (sell_opened)
  //   //{
  //   //  Alert("We already have a Sell Position!!!");
  //   //  return; // Don't open a new Sell Position
  //   //}

  //   tradeResult = MakeShortTrade(tradeRequest, tradeResult, bid, ask);

  //   if (tradeResult.retcode == 10009 || tradeResult.retcode == 10008) //Request is completed or order placed
  //   {
  //     Alert("A Sell order at ask price:", ask, " has been successfully placed with Ticket#:", tradeResult.order, "!!");
  //   }
  //   else
  //   {
  //     Alert("The Sell order request could not be completed -error:", GetLastError());
  //     ResetLastError();
  //     return;
  //   }

  //   positionTakenThisBar = true;
  // }

  isNewBar = false;
}

bool CheckForLong3BarPlay(MqlRates &barDetails[], double ask)
{
  double firstLargeGreenBarDistance = barDetails[3].close - barDetails[3].open;
  double secondBabyRedBarDistance = barDetails[2].open - barDetails[2].close;
  double thirdLargeGreenBarDistance = barDetails[1].close - barDetails[1].open;
  double barBeforeFirstLargeGreenBarDistance = barDetails[4].close - barDetails[4].open;
  
  if (barBeforeFirstLargeGreenBarDistance < 0)
  {
   barBeforeFirstLargeGreenBarDistance = barDetails[4].open - barDetails[4].close;
  }

  if (firstLargeGreenBarDistance == 0 || thirdLargeGreenBarDistance == 0)
  {
    return false;
  }
  //For easier debugging of which statement is incorrect

  if (currentTime == "2019.10.03 05:34")
  {
    Alert("Debugging Time");
  }

  // if (firstLargeGreenBarDistance > (secondBabyRedBarDistance * 2.5))
  // {
  //   Alert("First Green Bar is 2.5 times the size of the small Red Bar");
  // }
  // if (barDetails[3].close > barDetails[3].open)
  // {
  //   Alert("First Bar Green");
  // }
  // if (barDetails[2].close <= barDetails[2].open)
  // {
  //   Alert("Second Bar Red");
  // }
  // if (barDetails[1].close > barDetails[1].open)
  // {
  //   Alert("Third Bar Green");
  // }
  // if (barDetails[3].open < barDetails[2].close)
  // {
  //   Alert("");
  // }
  // if (barDetails[1].close > barDetails[2].open)
  // {
  //   Alert("");
  // }
  // if (
  //     barDetails[2].close <= (barDetails[3].close - (firstLargeGreenBarDistance / 5)) ||
  //     barDetails[2].close <= (barDetails[3].close + (firstLargeGreenBarDistance / 3)))
  // {
  //   Alert("");
  // }
  // if (barDetails[2].open <= (barDetails[1].open + (thirdLargeGreenBarDistance / 5)))
  // {
  //   Alert("");
  // }
  // if (barDetails[2].open <= (barDetails[1].close - (thirdLargeGreenBarDistance / 3)))
  // {
  //   Alert("");
  // }
  // if (thirdLargeGreenBarDistance > (secondBabyRedBarDistance * 2))
  // {
  //   Alert("");
  // }
  // if (barDetails[1].open <= barDetails[2].open)
  // {
  //   Alert("");
  // }
  // if (ask > ((barDetails[0].close * _Point) + (2 * _Point)))
  // {
  //   Alert("");
  // }

  bool result = firstLargeGreenBarDistance > (secondBabyRedBarDistance * mul1) &&
                barDetails[3].close > barDetails[3].open &&
                barDetails[2].close <= barDetails[2].open &&
                barDetails[1].close > barDetails[1].open &&
                barDetails[3].open < barDetails[2].close &&
                barDetails[1].close > barDetails[2].open &&
                (barDetails[2].close <= (barDetails[3].close - (firstLargeGreenBarDistance / div1)) ||
                 barDetails[2].close <= (barDetails[3].close + (firstLargeGreenBarDistance / div2))) &&
                barDetails[2].open <= (barDetails[1].open + (thirdLargeGreenBarDistance / div1)) &&
                barDetails[2].open <= (barDetails[1].close - (thirdLargeGreenBarDistance / div2)) &&
                thirdLargeGreenBarDistance > (secondBabyRedBarDistance * 2) &&
                barDetails[1].open <= barDetails[2].open && //Baby Red is in middle of bars
                ask > ((barDetails[0].close * _Point) + (mul2 * _Point)) && //Take position after price has reached Final Green candles close
                ((strictRule1 == 0) || (strictRule1 == 1 && (barDetails[3].close - barDetails[3].open) > (barDetails[3].open - barDetails[3].low))) && //First Green wick cant be bigger than its Candle
                ((strictRule2 == 0) || (strictRule2 == 1 && (barDetails[3].open < barDetails[2].low))) && //Baby wick cant be lower than First Green wick
                ((strictRule3 == 0) || (strictRule3 == 1 && (barBeforeFirstLargeGreenBarDistance < firstLargeGreenBarDistance))) && //Previous cant be Engulfing
                ((strictRule4 == 0) || (strictRule4 == 1 && 
                 ((barDetails[3].high - barDetails[3].close) < (barDetails[3].close + (firstLargeGreenBarDistance/div1))) && //Wicks cant be bigger than a fifth of the Candle 
                 ((barDetails[3].open - barDetails[3].low) < (barDetails[3].open + (firstLargeGreenBarDistance/div1))) && 
                 ((barDetails[1].high - barDetails[1].close) < (barDetails[1].close + (thirdLargeGreenBarDistance/div1))) && 
                 ((barDetails[1].open - barDetails[1].low) < (barDetails[1].open + (thirdLargeGreenBarDistance/div1)))));

  if (result == true)
  {
    Alert("Three bar play at Current bar -1");
  }
  
  return result;
}

MqlTradeResult MakeLongTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double bid, double ask)
{
  tradeRequest.action = TRADE_ACTION_DEAL; // immediate order execution

  tradeRequest.sl = NormalizeDouble(bid - STP * _Point, _Digits);
  tradeRequest.tp = NormalizeDouble(bid + TKP * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_BUY;            // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}

MqlTradeResult MakeShortTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double bid, double ask)
{
  tradeRequest.action = TRADE_ACTION_DEAL;

  tradeRequest.sl = NormalizeDouble(ask + STP * _Point, _Digits);
  tradeRequest.tp = NormalizeDouble(ask - TKP * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_SELL;           // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}