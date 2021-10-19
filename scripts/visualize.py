import matplotlib.pyplot as plt
import csv
import os.path


bidNumber = []
raffleCost = []
auctionCost = []

curPath = os.path.abspath(os.path.dirname(__file__))
inputPath = os.path.join(curPath, "../output/gascosts.csv")
outputPath = os.path.join(curPath, "../output/plot.png")

  
with open(inputPath,'r') as csvfile:
    reader = csv.DictReader(csvfile)
    for row in reader:
        bidNumber.append(int(row['bidNumber']))
        auctionCost.append(int(row['batchAuctionCost']))
        raffleCost.append(int(row['multiRaffleCost']))


fig = plt.figure()
ax1 = fig.add_subplot(111)

ax1.scatter(bidNumber, raffleCost, s=10, c='b', marker="s", label='raffle cost')
ax1.scatter(bidNumber, auctionCost, s=10, c='r', marker="o", label='auction cost')

ax1.set_ylabel('gas cost')
ax1.set_xlabel('number of entries')
ax1.set_title('Gas cost comparison: raffle vs auction')

bottom, top = plt.ylim() 
plt.ylim(0, top)

plt.legend(loc='lower left')

plt.savefig(outputPath)
