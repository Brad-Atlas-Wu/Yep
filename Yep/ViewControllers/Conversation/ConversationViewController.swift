//
//  ConversationViewController.swift
//  Yep
//
//  Created by NIX on 15/3/23.
//  Copyright (c) 2015年 Catch Inc. All rights reserved.
//

import UIKit
import Realm

class ConversationViewController: UIViewController {

    var conversation: Conversation!

    lazy var messages: RLMResults = {
        return messagesInConversation(self.conversation)
        }()

    @IBOutlet weak var conversationCollectionView: UICollectionView!

    @IBOutlet weak var messageToolbar: MessageToolbar!
    @IBOutlet weak var messageToolbarBottomConstraint: NSLayoutConstraint!

    let messageTextAttributes = [NSFontAttributeName: UIFont.systemFontOfSize(13)] // TODO: 用配置来决定
    let messageTextLabelMaxWidth: CGFloat = 320 - (15+40+20) - 20 // TODO: 根据 TextCell 的布局计算


    lazy var collectionViewWidth: CGFloat = {
        return CGRectGetWidth(self.conversationCollectionView.bounds)
        }()

    let chatLeftTextCellIdentifier = "ChatLeftTextCell"
    let chatRightTextCellIdentifier = "ChatRightTextCell"


    // 使 messageToolbar 随着键盘出现或消失而移动
    var updateUIWithKeyboardChange = false {
        willSet {
            keyboardChangeObserver = newValue ? NSNotificationCenter.defaultCenter() : nil
        }
    }
    var keyboardChangeObserver: NSNotificationCenter? {
        didSet {
            oldValue?.removeObserver(self, name: UIKeyboardWillShowNotification, object: nil)
            oldValue?.removeObserver(self, name: UIKeyboardWillHideNotification, object: nil)

            keyboardChangeObserver?.addObserver(self, selector: "handleKeyboardWillShowNotification:", name: UIKeyboardWillShowNotification, object: nil)
            keyboardChangeObserver?.addObserver(self, selector: "handleKeyboardWillHideNotification:", name: UIKeyboardWillHideNotification, object: nil)
        }
    }


    deinit {
        updateUIWithKeyboardChange = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        conversationCollectionView.registerNib(UINib(nibName: chatLeftTextCellIdentifier, bundle: nil), forCellWithReuseIdentifier: chatLeftTextCellIdentifier)
        conversationCollectionView.registerNib(UINib(nibName: chatRightTextCellIdentifier, bundle: nil), forCellWithReuseIdentifier: chatRightTextCellIdentifier)

        setConversaitonCollectionViewOriginalContentInset()

        messageToolbarBottomConstraint.constant = 0

        updateUIWithKeyboardChange = true

        messageToolbar.textSendAction = { messageToolbar in
            let text = messageToolbar.messageTextField.text!

            if let withFriend = self.conversation.withFriend {
                sendText(text, toRecipient: withFriend.userID, recipientType: "User", failureHandler: { (reason, errorMessage) -> () in
                    defaultFailureHandler(reason, errorMessage)
                    // TODO: sendText 错误提醒

                }, completion: { success -> Void in
                    println("sendText: \(success)")

                    // 完成后，Message 就插入数据库了，下面插入 Cell 才有可能
                    dispatch_async(dispatch_get_main_queue()) {
                        self.updateUIAfterSentText(text)
                    }
                })
            } else if let withGroup = self.conversation.withGroup {
                sendText(text, toRecipient: withGroup.groupID, recipientType: "Circle", failureHandler: { (reason, errorMessage) -> () in
                    defaultFailureHandler(reason, errorMessage)
                    // TODO: sendText 错误提醒

                }, completion: { success -> Void in
                    println("sendText: \(success)")

                    // 完成后，Message 就插入数据库了，下面插入 Cell 才有可能
                    dispatch_async(dispatch_get_main_queue()) {
                        self.updateUIAfterSentText(text)
                    }
                })
            }
        }
    }

    // MARK: Private

    private func setConversaitonCollectionViewOriginalContentInsetBottom(bottom: CGFloat) {
        var contentInset = conversationCollectionView.contentInset
        contentInset.bottom = bottom
        conversationCollectionView.contentInset = contentInset
    }

    private func setConversaitonCollectionViewOriginalContentInset() {
        setConversaitonCollectionViewOriginalContentInsetBottom(messageToolbar.intrinsicContentSize().height)
    }

    // MARK: Actions

    func updateUIAfterSentText(text: String) {
        // 先重新准备 Layout
        let layout = self.conversationCollectionView.collectionViewLayout as! ConversationLayout
        layout.needUpdate = true

        // 再插入 Cell
        let newMessageIndexPath = NSIndexPath(forItem: self.conversation.messages.count - 1, inSection: 0)
        self.conversationCollectionView.insertItemsAtIndexPaths([newMessageIndexPath])

        UIView.animateWithDuration(0.2, delay: 0.0, options: UIViewAnimationOptions.CurveEaseInOut, animations: { () -> Void in
            // TODO: 不使用魔法数字
            let rect = text.boundingRectWithSize(CGSize(width: self.messageTextLabelMaxWidth, height: CGFloat(FLT_MAX)), options: .UsesLineFragmentOrigin | .UsesFontLeading, attributes: self.messageTextAttributes, context: nil)

            let height = max(rect.height + 14 + 20, 40 + 20) + 10
            self.conversationCollectionView.contentOffset.y += height

            }, completion: { (finished) -> Void in

        })

        // Clean
        self.messageToolbar.messageTextField.text = ""
        self.messageToolbar.state = .Default
    }

    // MARK: Keyboard

    func handleKeyboardWillShowNotification(notification: NSNotification) {
        println("showKeyboard") // 在 iOS 8.3 Beat 3 里，首次弹出键盘时，这个通知会发出三次，下面设置 contentOffset 因执行多次就会导致跳动。但第二次弹出键盘就不会了

        if let userInfo = notification.userInfo {

            let animationDuration: NSTimeInterval = (userInfo[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue
            let animationCurveValue = (userInfo[UIKeyboardAnimationCurveUserInfoKey] as! NSNumber).unsignedLongValue
            let keyboardEndFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as! NSValue).CGRectValue()
            let keyboardHeight = keyboardEndFrame.height

            UIView.animateWithDuration(animationDuration, delay: 0, options: UIViewAnimationOptions(animationCurveValue << 16), animations: { () -> Void in
                self.messageToolbarBottomConstraint.constant = keyboardHeight
                self.view.layoutIfNeeded()

                self.conversationCollectionView.contentOffset.y += keyboardHeight
                self.conversationCollectionView.contentInset.bottom += keyboardHeight

            }, completion: { (finished) -> Void in
            })
        }
    }

    func handleKeyboardWillHideNotification(notification: NSNotification) {
        println("hideKeyboard")

        if let userInfo = notification.userInfo {
            let animationDuration: NSTimeInterval = (userInfo[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue
            let animationCurveValue = (userInfo[UIKeyboardAnimationCurveUserInfoKey] as! NSNumber).unsignedLongValue
            let keyboardEndFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as! NSValue).CGRectValue()
            let keyboardHeight = keyboardEndFrame.height

            UIView.animateWithDuration(animationDuration, delay: 0, options: UIViewAnimationOptions(animationCurveValue << 16), animations: { () -> Void in
                self.messageToolbarBottomConstraint.constant = 0
                self.view.layoutIfNeeded()

                self.conversationCollectionView.contentOffset.y -= keyboardHeight
                self.conversationCollectionView.contentInset.bottom -= keyboardHeight

            }, completion: { (finished) -> Void in
            })
        }
    }
}

// MARK: UICollectionViewDataSource, UICollectionViewDelegate

extension ConversationViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return conversation.messages.count
    }

    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {

        let message = messages.objectAtIndex(UInt(indexPath.row)) as! Message

        if let sender = message.fromFriend {
            if sender.friendState != UserFriendState.Me.rawValue {
                let cell = collectionView.dequeueReusableCellWithReuseIdentifier(chatLeftTextCellIdentifier, forIndexPath: indexPath) as! ChatLeftTextCell

                cell.textContentLabel.text = message.textContent

                AvatarCache.sharedInstance.roundAvatarOfUser(sender, withRadius: 40 * 0.5) { roundImage in
                    dispatch_async(dispatch_get_main_queue()) {
                        cell.avatarImageView.image = roundImage
                    }
                }

                return cell

            } else {
                let cell = collectionView.dequeueReusableCellWithReuseIdentifier(chatRightTextCellIdentifier, forIndexPath: indexPath) as! ChatRightTextCell

                cell.textContentLabel.text = message.textContent

                AvatarCache.sharedInstance.roundAvatarOfUser(sender, withRadius: 40 * 0.5) { roundImage in
                    dispatch_async(dispatch_get_main_queue()) {
                        cell.avatarImageView.image = roundImage
                    }
                }

                return cell
            }

        } else {
            println("Conversation: Should not be there")

            let cell = collectionView.dequeueReusableCellWithReuseIdentifier(chatRightTextCellIdentifier, forIndexPath: indexPath) as! ChatRightTextCell

            cell.textContentLabel.text = ""
            cell.avatarImageView.image = AvatarCache.sharedInstance.defaultRoundAvatarOfRadius(40 * 0.5)

            return cell
        }
    }

    func collectionView(collectionView: UICollectionView!, layout collectionViewLayout: UICollectionViewLayout!, sizeForItemAtIndexPath indexPath: NSIndexPath!) -> CGSize {

        // TODO: 缓存 Cell 高度才是正道
        // TODO: 不使用魔法数字
        let message = messages.objectAtIndex(UInt(indexPath.row)) as! Message

        let rect = message.textContent.boundingRectWithSize(CGSize(width: messageTextLabelMaxWidth, height: CGFloat(FLT_MAX)), options: .UsesLineFragmentOrigin | .UsesFontLeading, attributes: messageTextAttributes, context: nil)

        let height = max(rect.height + 14 + 20, 40 + 20)
        return CGSizeMake(collectionViewWidth, height)
    }

    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        view.endEditing(true)
    }
}


