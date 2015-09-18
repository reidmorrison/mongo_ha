## Testing

Unfortunately the only way to properly test mongo_ha is to startup a console with connections
active and to stop / restart the mongo servers in the replicaset as follows:


#### Run the following code in a console

```ruby
collection = Cache::Identity.database['test']
collection.drop
threads = 5.times.collect do |i|
  Thread.new do
    100.times do |j|
      1_000.times do |k|
        collection.insert(_id: "#{i}-#{j}-#{k}")
        collection.find_one(_id: "#{i}-#{j}-#{k}")
        puts("#{i}-#{j}-#{k}") if k % 1000 == 0
      end
      puts "#{i}-#{j} pausing"
      sleep 5
    end
    puts "#{i} Complete"
  end
end
```

#### Steps

While running the above code in the console

* Stop 1 slave server

Nothing should appear in the logs and everything should process fine

* Stop another slave

The logs should show retries

* Start up one of the 2 slaves that were stopped

The processing should resume successfully

#### To stop the test

```ruby
threads.each(&:kill)
```
