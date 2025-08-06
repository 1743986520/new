#include <iostream>
#include <vector>
#include <conio.h>
#include <windows.h>
#include <string>
#include <algorithm>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <ctime>

using namespace std;

struct Point {
    int x;
    int y;
    bool operator==(const Point& other) const {
        return x == other.x && y == other.y;
    }
};

class SnakeGame {
public:
    SnakeGame() {
        srand(time(NULL));
        gameOver = false;
        dir = 'd';
        score = 0;
        initSnake();
        generateFood();
    }

    void Run() {
        while (!gameOver) {
            draw();
            input();
            move();
            checkCollision();
            Sleep(500);
        }
    }

private:
    vector<Point> snake;
    Point food;
    bool gameOver;
    char dir;
    int score;

    void initSnake() {
        for (int i = 0; i < 3; ++i) {
            snake.push_back({ 10 + i, 10 });
        }
    }

    void generateFood() {
        while (true) {
            Point newFood = { rand() % 20, rand() % 20 };
            bool onSnake = false;
            for (const auto& segment : snake) {
                if (segment == newFood) {
                    onSnake = true;
                    break;
                }
            }
            if (!onSnake) {
                food = newFood;
                break;
            }
        }
    }

    void draw() {
        system("cls");
        for (int y = 0; y < 20; ++y) {
            for (int x = 0; x < 20; ++x) {
                Point p = { x, y };
                bool isSnake = false;
                for (const auto& segment : snake) {
                    if (segment == p) {
                        isSnake = true;
                        break;
                    }
                }
                if (p == food) {
                    cout << "$";
                }
                else if (isSnake) {
                    cout << "O";
                }
                else {
                    cout << ".";
                }
            }
            cout << endl;
        }
        cout << "Score: " << score << endl;
    }

    void input() {
        if (_kbhit()) {
            char newDir = _getch();
            if (newDir == 'w' || newDir == 'a' || newDir == 's' || newDir == 'd') {
                dir = newDir;
            }
        }
    }

    void move() {
        Point newHead = snake[0];
        switch (dir) {
        case 'w': newHead.y--; break;
        case 's': newHead.y++; break;
        case 'a': newHead.x--; break;
        case 'd': newHead.x++; break;
        }

        snake.insert(snake.begin(), newHead);

        if (newHead == food) {
            score += 10;
            generateFood();
        }
        else {
            snake.pop_back();
        }
    }

    void checkCollision() {
        Point head = snake[0];
        if (head.x < 0 || head.x >= 20 || head.y < 0 || head.y >= 20) {
            gameOver = true;
            cout << "Game Over! You hit the wall." << endl;
            return;
        }
        for (size_t i = 1; i < snake.size(); ++i) {
            if (snake[i] == head) {
                gameOver = true;
                cout << "Game Over! You hit yourself." << endl;
                return;
            }
        }
    }
};

int main() {
    SnakeGame game;
    game.Run();
    return 0;
}
