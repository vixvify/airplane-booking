#ifndef WORKER_H
#define WORKER_H

#include "work_queue.h"

void receiveRequests(int requestQueueId, WorkQueue& workQueue);

void worker(
    int workerId,
    WorkQueue& workQueue
);

#endif
