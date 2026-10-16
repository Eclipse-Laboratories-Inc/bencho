# Update coverage report

```
forge coverage --report lcov --report-file ./test/coverage/lcov.info
genhtml -o ./test/coverage_report ./test/coverage/lcov.info
```

This creates a static web site in `./test/coverage-report`. Serve that with your favorite static HTML server, such as `serve`. 

## Dependencies

If you don't have `lcov`, install with (Ubuntu):

```
sudo apt-get install lcov
```

