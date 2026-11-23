set dotenv-load

default:
    @just --list

build:
    swift build -c release

install:
    swift run -c release slybar install

test:
    swift test

dev *args:
    swift run slybar {{args}}
