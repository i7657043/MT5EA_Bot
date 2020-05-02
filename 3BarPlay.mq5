//+------------------------------------------------------------------+
//|                                                     3BarPlay.mq5 |
//|                                                               JG |
//|                                                             None |
//+------------------------------------------------------------------+
//--- input parameters
input bool stopLossPrice=false;             //Set StopLoss at bottom of baby red bar
input int stopLoss = 64;                    //Stop Loss
input int takeProfit = 113;                 //Take Profit
input int barIntervalThreshold = 6;         // Bar Trade interval

//---Optimisation input parameters
input double babyBarOverallSizeArg=2;   //Outer bars must be X times the size of the baby bar
input double outerBoundaryThreshold=5;  //Lower number = tighter outer boundaries
input double takePositionThreshold=2;   //Enter after price = final bar close + X points
input bool babyRedEnglufed=false;       //Baby red bar cant be totally engulfed by either Green bar
input bool outerGreensEngulfed=false;   //Baby red bar wick shoudln't engulf either outer green bar body

//--- Other parameters
int movingAveragePeriod = 50;
int expertAdvisorMagicNumber = 12345;
double lotSize = 0.01;               

int movingAverageHandler; // handle for our Moving Average indicator
double movingAverages[];  // Dynamic array to hold the values of Moving Average for each bars

string currentTime = "";
bool isNewBar = false;

bool positionTakenThisBar = false;
bool tradeBarCounterActive = 0;
int barsSinceLastTrade = 0;

int OnInit()
{
 //--- Get the handle for Moving Average indicator
  movingAverageHandler = iMA(_Symbol, _Period, movingAveragePeriod, 0, MODE_EMA, PRICE_CLOSE);

  //--- What if handle returns Invalid Handle
  if (movingAverageHandler < 0)
  {
    Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
  }
  
  return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
  IndicatorRelease(movingAverageHandler);
}

void OnTick()
{
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
    if (barsSinceLastTrade > barIntervalThreshold)
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
  
  MqlTick latestPriceDetails;   // To be used for getting recent/latest price quotes
  MqlTradeRequest tradeRequest; // To be used for sending our trade requests
  MqlTradeResult tradeResult;   // To be used to get our trade results
  MqlRates barDetails[];        // To be used to store the prices, volumes and spread of each bar
  ZeroMemory(tradeRequest);     // Initialization of tradeRequest struct
  
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

  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  int spread = (int)MathRound((ask - bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));

  if (tradeBarCounterActive == false && positionTakenThisBar == false && CheckForLong3BarPlay(barDetails, ask))
  {
    tradeResult = MakeLongTrade(tradeRequest, tradeResult, bid, stopLossPrice, barDetails[2].close);

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
  
  //For easier debugging of which statement is incorrect
  if (currentTime == "2019.10.03 05:34")
  {
    Alert("Debugging Time");
  }  
  
  //Check bars are correct type, baby red can be Doji bar
  if (firstLargeGreenBarDistance <= 0 || thirdLargeGreenBarDistance <= 0 || secondBabyRedBarDistance < 0)  
  {
    return false;
  }
  
  //Outer bars must be X times the size of the baby bar
  if (!(firstLargeGreenBarDistance > (secondBabyRedBarDistance * babyBarOverallSizeArg)) ||
      !(thirdLargeGreenBarDistance > (secondBabyRedBarDistance * babyBarOverallSizeArg)))
  {
    return false;
  }
  
  //Top of baby red bar must be below top Xth of third green bar
  //And
  //Bottom of baby red bar must be above bottom Xth of first green bar
  //This Rule makes sure outer green bars totally surround BODY of baby red, but not Wick
  if (!(barDetails[2].open <= (barDetails[1].close - (thirdLargeGreenBarDistance / outerBoundaryThreshold))) ||
      !(barDetails[2].close >= (barDetails[3].open + (firstLargeGreenBarDistance / outerBoundaryThreshold))))
  {
   return false;
  }
  
  //Baby red bar wick shoudln't engulf either outer green bar body
  //If this is on there is no need for below Rule as this is Tighter
  if (outerGreensEngulfed && ((barDetails[2].high > barDetails[3].close) && (barDetails[2].low < barDetails[3].open)) ||
      ((barDetails[2].high > barDetails[1].close) && (barDetails[2].low < barDetails[3].open)))
  {
   return false;
  }  
  //Baby red bar wick shoudln't engulf either outer green bar range 
  //if (((barDetails[2].high > barDetails[3].high) && (barDetails[2].low < barDetails[3].low)) ||
  //    ((barDetails[2].high > barDetails[1].high) && (barDetails[2].low < barDetails[3].low)))
  //{
  //  return false;
  //}
  
  //Top of first green bar must be below top of baby red bar
  //AND
  //Bottom of third green bar must be above bottom of baby red bar
  //This Rule stops the baby red bar being Engulfed by either outer green bar
  //i.e. the baby red bar must run over into both green bars
  if (babyRedEnglufed && !(barDetails[3].close < barDetails[2].open) || 
      !(barDetails[1].open > barDetails[2].close))
  {
   return false;
  }  
  
  //Take position after price has reached Final Green candles close + X points
  if (!(ask >= ((barDetails[0].close * _Point) + (takePositionThreshold * _Point))))
  {
   return false;
  }    
  
  return true;
}

MqlTradeResult MakeLongTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double bid, bool stopLossPrice, double babyBarClosePrice)
{
  tradeRequest.action = TRADE_ACTION_DEAL; // immediate order execution

  if (stopLossPrice)
  {
   tradeRequest.sl = NormalizeDouble(babyBarClosePrice, _Digits);
  }
  else
  {
   tradeRequest.sl = NormalizeDouble(bid - stopLoss * _Point, _Digits);
  }
  
  tradeRequest.tp = NormalizeDouble(bid + takeProfit * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_BUY;            // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}

MqlTradeResult MakeShortTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double bid, double ask, bool stopLossPrice)
{
  tradeRequest.action = TRADE_ACTION_DEAL;

  if (stopLossPrice)
  {
   tradeRequest.sl = NormalizeDouble(stopLossPrice, _Digits);
  }
  else
  {
   tradeRequest.sl = NormalizeDouble(ask + stopLoss * _Point, _Digits);
  }
  
  tradeRequest.tp = NormalizeDouble(ask - takeProfit * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_SELL;           // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}