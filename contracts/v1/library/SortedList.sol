// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "../interfaces/IStakePool.sol";

library SortedLinkedList {
    struct List {
        IStakePool head;
        IStakePool tail;
        uint8 length;
        mapping(IStakePool => IStakePool) prev;
        mapping(IStakePool => IStakePool) next;
    }

    function improveRanking(List storage _list, IStakePool _value)
    internal {
        //insert new
        if (_list.length == 0) {
            _list.head = _value;
            _list.tail = _value;
            _list.length++;
            return;
        }

        //already first
        if (_list.head == _value) {
            return;
        }

        IStakePool _prev = _list.prev[_value];
        // not in list
        if (_prev == IStakePool(0)) {
            //insert new
            _list.length++;

            if (_value.totalStake() <= _list.tail.totalStake()) {
                _list.prev[_value] = _list.tail;
                _list.next[_list.tail] = _value;
                _list.tail = _value;

                return;
            }

            _prev = _list.tail;
        } else {
            if (_value.totalStake() <= _prev.totalStake()) {
                return;
            }

            //remove from list
            _list.next[_prev] = _list.next[_value];
            if (_value == _list.tail) {
                _list.tail = _prev;
            } else {
                _list.prev[_list.next[_value]] = _list.prev[_value];
            }
        }

        while (_prev != IStakePool(0) && _value.totalStake() > _prev.totalStake()) {
            _prev = _list.prev[_prev];
        }

        if (_prev == IStakePool(0)) {
            _list.next[_value] = _list.head;
            _list.prev[_list.head] = _value;
            _list.prev[_value] = IStakePool(0);
            _list.head = _value;
        } else {
            _list.next[_value] = _list.next[_prev];
            _list.prev[_list.next[_prev]] = _value;
            _list.next[_prev] = _value;
            _list.prev[_value] = _prev;
        }
    }


    function lowerRanking(List storage _list, IStakePool _value)
    internal {
        IStakePool _next = _list.next[_value];
        if (_list.tail == _value || _next == IStakePool(0) || _next.totalStake() <= _value.totalStake()) {
            return;
        }

        //remove it
        _list.prev[_next] = _list.prev[_value];
        if (_list.head == _value) {
            _list.head = _next;
        } else {
            _list.next[_list.prev[_value]] = _next;
        }

        while (_next != IStakePool(0) && _next.totalStake() > _value.totalStake()) {
            _next = _list.next[_next];
        }

        if (_next == IStakePool(0)) {
            _list.prev[_value] = _list.tail;
            _list.next[_value] = IStakePool(0);

            _list.next[_list.tail] = _value;
            _list.tail = _value;
        } else {
            _list.next[_list.prev[_next]] = _value;
            _list.prev[_value] = _list.prev[_next];
            _list.next[_value] = _next;
            _list.prev[_next] = _value;
        }
    }


    function removeRanking(List storage _list, IStakePool _value)
    internal {
        if (_list.head != _value && _list.prev[_value] == IStakePool(0)) {
            //not in list
            return;
        }

        if (_list.tail == _value) {
            _list.tail = _list.prev[_value];
        }

        if (_list.head == _value) {
            _list.head = _list.next[_value];
        }

        IStakePool _next = _list.next[_value];
        if (_next != IStakePool(0)) {
            _list.prev[_next] = _list.prev[_value];
        }
        IStakePool _prev = _list.prev[_value];
        if (_prev != IStakePool(0)) {
            _list.next[_prev] = _list.next[_value];
        }

        _list.prev[_value] = IStakePool(0);
        _list.next[_value] = IStakePool(0);
        _list.length--;
    }
}
